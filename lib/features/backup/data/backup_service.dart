import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../config/app_config.dart';
import '../../../core/errors/paper_exception.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/storage/paper_schema.dart';
import '../../../core/utils/ids.dart';
import '../../annotations/domain/annotation.dart';
import '../../library/domain/document.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/domain/app_settings.dart';
import '../domain/backup_manifest.dart';
import 'backup_archive.dart';

/// A completed archive and the manifest it was built from.
class BackupResult {
  const BackupResult({
    required this.path,
    required this.manifest,
    required this.byteSize,
  });

  final String path;
  final BackupManifest manifest;
  final int byteSize;
}

/// What a successful full replacement changed.
class RestoreResult {
  const RestoreResult({
    required this.counts,
    required this.safetySnapshotPath,
    required this.warnings,
  });

  final BackupCounts counts;
  final String safetySnapshotPath;
  final List<String> warnings;
}

/// Creates and restores complete `.paperosbackup` archives.
///
/// A restore is a full replacement, never a merge: the backup is what the user
/// asked for, and quietly combining two libraries has no defined winner for
/// reading progress. Nothing is deleted until the archive, its checksums, the
/// JSON, a real staging SQLite database and every relationship have passed
/// validation. A private safety snapshot is taken first.
class BackupService {
  BackupService({
    required AppDatabaseOpener database,
    required AppStorage storage,
    required SettingsRepository settings,
    sqflite.DatabaseFactory? databaseFactory,
  }) : _database = database,
       _storage = storage,
       _settings = settings,
       _factory = databaseFactory ?? sqflite.databaseFactory;

  final AppDatabaseOpener _database;
  final AppStorage _storage;
  final SettingsRepository _settings;
  final sqflite.DatabaseFactory _factory;

  Future<BackupPreview> inspect({
    required String archivePath,
    required String displayName,
  }) async {
    try {
      final BackupManifest manifest = await BackupArchive.inspect(archivePath);
      return BackupPreview(
        archivePath: archivePath,
        displayName: displayName,
        archiveBytes: await File(archivePath).length(),
        manifest: manifest,
      );
    } on FormatException catch (error) {
      throw PaperException.corruptDocument(error.message, cause: error);
    } on FileSystemException catch (error) {
      throw PaperException.storage(
        'PaperOS could not read that backup file.',
        cause: error,
      );
    }
  }

  /// Writes a complete archive into app-private storage. The caller is
  /// responsible for handing it to the system save picker and then deleting it.
  Future<BackupResult> createBackup({
    required AppSettings settings,
    void Function(BackupProgress progress)? onProgress,
    bool Function()? isCancelled,
    bool safetySnapshot = false,
  }) async {
    final Directory workRoot = await _storage.backupStaging();
    final Directory work = Directory(
      p.join(workRoot.path, 'work-${newLocalId()}'),
    );
    await work.create(recursive: true);
    File? output;
    try {
      if (isCancelled?.call() == true) {
        throw const BackupCancelledException();
      }
      onProgress?.call(
        const BackupProgress(fraction: 0, message: 'Reading the library'),
      );
      final Map<String, List<Map<String, Object?>>> tables =
          await _snapshotTables();
      final BackupCounts counts = BackupCounts.fromTables(tables);
      final Directory library = await _storage.library();
      final Directory covers = await _storage.covers();
      final List<String> warnings = <String>[];
      final List<_SourceFile> books = <_SourceFile>[];
      final List<_SourceFile> coverFiles = <_SourceFile>[];
      final List<Map<String, Object?>> documents = tables['documents']!;
      if (documents.length > PaperConfig.maxBackupDocuments) {
        throw PaperException.storage(
          'The library has more than ${PaperConfig.maxBackupDocuments} '
          'documents. Remove some before creating a backup.',
        );
      }
      int documentIndex = 0;
      for (final Map<String, Object?> row in documents) {
        documentIndex++;
        final String id = _databaseString(row['id']);
        final String title = _databaseString(row['title']);
        final String localPath = _databaseString(row['local_path']);
        final File file = File(localPath);
        if (!_isInside(library.path, localPath)) {
          throw PaperException.storage(
            'The stored file for "$title" is outside PaperOS storage, so it '
            'cannot be backed up safely.',
          );
        }
        if (!file.existsSync()) {
          throw PaperException.missingFile(
            '"$title" is missing its file. Remove the missing entry from the '
            'library, then create the backup again.',
          );
        }
        final int length = file.lengthSync();
        if (length > PaperConfig.maxBackupEntryBytes) {
          throw PaperException.storage(
            '"$title" is larger than the maximum PaperOS library file size.',
          );
        }
        final String extension = _safeExtension(localPath);
        row['byte_size'] = length;
        books.add(
          _SourceFile(
            documentId: id,
            file: file,
            archivePath:
                'books/${documentIndex.toString().padLeft(6, '0')}$extension',
            kind: 'book',
          ),
        );
        final String? coverPath = row['cover_path'] as String?;
        if (coverPath != null && coverPath.isNotEmpty) {
          final File cover = File(coverPath);
          if (!_isInside(covers.path, coverPath) || !cover.existsSync()) {
            // A cover is metadata, not the book. Losing it should not block a
            // backup, but the backup must be honest that it has no cover.
            row['cover_path'] = null;
            warnings.add(
              'The cover for "$title" was missing and was not saved.',
            );
          } else {
            coverFiles.add(
              _SourceFile(
                documentId: id,
                file: cover,
                archivePath:
                    'covers/${documentIndex.toString().padLeft(6, '0')}'
                    '${_safeExtension(coverPath)}',
                kind: 'cover',
              ),
            );
          }
        }
      }

      if (isCancelled?.call() == true) {
        throw const BackupCancelledException();
      }
      final Map<String, Object?> databaseDocument = <String, Object?>{
        'format': 'paperos.database',
        'version': 1,
        'schemaVersion': PaperConfig.databaseVersion,
        'tables': tables,
      };
      final List<int> databaseBytes = utf8.encode(jsonEncode(databaseDocument));
      final File databaseFile = File(p.join(work.path, 'database.json'));
      await databaseFile.writeAsBytes(databaseBytes, flush: true);

      final List<int> settingsBytes = utf8.encode(
        _settings.exportJson(settings),
      );
      final File settingsFile = File(p.join(work.path, 'settings.json'));
      await settingsFile.writeAsBytes(settingsBytes, flush: true);

      onProgress?.call(
        const BackupProgress(
          fraction: 0.1,
          message: 'Writing the library manifest',
        ),
      );
      final String databaseHash = _hashBytes(databaseBytes);
      final String settingsHash = _hashBytes(settingsBytes);
      final List<BackupEntry> entries = <BackupEntry>[
        BackupEntry(
          path: 'database.json',
          type: BackupEntryType.database,
          byteSize: databaseBytes.length,
          sha256: databaseHash,
        ),
        BackupEntry(
          path: 'settings.json',
          type: BackupEntryType.settings,
          byteSize: settingsBytes.length,
          sha256: settingsHash,
        ),
      ];
      int libraryBytes = 0;
      Future<void> addSources(List<_SourceFile> sources) async {
        for (final _SourceFile source in sources) {
          final int length = source.file.lengthSync();
          final String hash = await _hashFile(source.file);
          entries.add(
            BackupEntry(
              path: source.archivePath,
              type: source.kind == 'book'
                  ? BackupEntryType.book
                  : BackupEntryType.cover,
              byteSize: length,
              sha256: hash,
              documentId: source.documentId,
            ),
          );
          libraryBytes += length;
        }
      }

      await addSources(books);
      await addSources(coverFiles);

      // Refuse to write an archive that the same version would refuse to
      // restore. Limits are shared with BackupArchive rather than duplicated.
      if (entries.length > PaperConfig.maxBackupEntries) {
        throw PaperException.storage(
          'This library exceeds the '
          '${PaperConfig.maxBackupEntries}-file backup limit.',
        );
      }
      final int totalBytes =
          databaseBytes.length + settingsBytes.length + libraryBytes;
      if (totalBytes > PaperConfig.maxBackupUncompressedBytes) {
        throw PaperException.storage(
          'This library is larger than the '
          '${PaperConfig.maxBackupUncompressedBytes ~/ (1024 * 1024 * 1024)} GB '
          'backup limit.',
        );
      }

      final BackupManifest manifest = BackupManifest(
        format: PaperConfig.backupFormat,
        version: PaperConfig.backupFormatVersion,
        appVersion: PaperConfig.versionLabel,
        schemaVersion: PaperConfig.databaseVersion,
        createdAt: DateTime.now().toUtc(),
        counts: counts,
        entries: List<BackupEntry>.unmodifiable(entries),
        libraryBytes: libraryBytes,
        warnings: List<String>.unmodifiable(warnings),
      );
      final List<int> manifestBytes = utf8.encode(
        jsonEncode(manifest.toJson()),
      );
      final File manifestFile = File(p.join(work.path, 'manifest.json'));
      await manifestFile.writeAsBytes(manifestBytes, flush: true);
      final File checksumFile = File(p.join(work.path, 'manifest.sha256'));
      await checksumFile.writeAsString(
        '${_hashBytes(manifestBytes)}  manifest.json\n',
        flush: true,
      );

      final String stamp = _fileStamp(DateTime.now());
      final String prefix = safetySnapshot
          ? 'PaperOS-safety'
          : 'PaperOS Back-up';
      final Directory outputDirectory = safetySnapshot
          ? await _storage.safetyBackups()
          : workRoot;
      File archive = File(
        p.join(outputDirectory.path, '$prefix $stamp.paperosbackup'),
      );
      output = archive;
      int attempt = 1;
      while (archive.existsSync()) {
        archive = File(
          p.join(
            outputDirectory.path,
            '$prefix $stamp-${attempt++}.paperosbackup',
          ),
        );
        output = archive;
      }

      onProgress?.call(
        const BackupProgress(
          fraction: 0.15,
          message: 'Packing documents and records',
        ),
      );
      final List<_SourceFile> allSources = <_SourceFile>[
        ...books,
        ...coverFiles,
      ];
      final int total = allSources.length + 4;
      final ZipFileEncoder encoder = ZipFileEncoder();
      bool encoderOpen = false;
      try {
        encoder.create(archive.path, level: ZipFileEncoder.gzip);
        encoderOpen = true;
        await encoder.addFile(databaseFile, 'database.json');
        await encoder.addFile(settingsFile, 'settings.json');
        int written = 2;
        for (final _SourceFile source in allSources) {
          if (isCancelled?.call() == true) {
            throw const BackupCancelledException();
          }
          await encoder.addFile(
            source.file,
            source.archivePath,
            ZipFileEncoder.store,
          );
          written++;
          onProgress?.call(
            BackupProgress(
              fraction: 0.15 + 0.8 * (written / total),
              message:
                  'Saving ${source.kind == 'book' ? 'book' : 'cover'} '
                  '$written of $total',
            ),
          );
        }
        await encoder.addFile(manifestFile, 'manifest.json');
        await encoder.addFile(checksumFile, 'manifest.sha256');
        await encoder.close();
        encoderOpen = false;
      } catch (_) {
        if (encoderOpen) {
          try {
            await encoder.close();
          } on Object {
            // The partial archive is deleted below.
          }
        }
        rethrow;
      }

      if (isCancelled?.call() == true) {
        throw const BackupCancelledException();
      }
      onProgress?.call(
        const BackupProgress(fraction: 0.98, message: 'Checking the archive'),
      );
      await BackupArchive.inspect(archive.path);
      final int byteSize = await archive.length();
      if (safetySnapshot) await _pruneSafetyBackups(archive.path);
      onProgress?.call(
        const BackupProgress(fraction: 1, message: 'Backup ready'),
      );
      return BackupResult(
        path: archive.path,
        manifest: manifest,
        byteSize: byteSize,
      );
    } on BackupCancelledException {
      if (output != null) _deleteFileQuietly(output);
      rethrow;
    } on PaperException {
      if (output != null) _deleteFileQuietly(output);
      rethrow;
    } on FormatException catch (error) {
      if (output != null) _deleteFileQuietly(output);
      throw PaperException.storage(
        'PaperOS could not create a consistent backup: ${error.message}',
        cause: error,
      );
    } on FileSystemException catch (error) {
      if (output != null) _deleteFileQuietly(output);
      throw PaperException.storage(
        'PaperOS could not write the backup. Check that the device has '
        'enough free space.',
        cause: error,
      );
    } finally {
      try {
        if (work.existsSync()) await work.delete(recursive: true);
      } on FileSystemException {
        // Disposable work data; a later startup can remove it.
      }
    }
  }

  Future<RestoreResult> restore({
    required BackupPreview preview,
    required AppSettings currentSettings,
    void Function(BackupProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final List<String> newFiles = <String>[];
    bool committed = false;

    // Only roll back copied attachments while the database still points at the
    // old library. Once the transaction commits, these files are the live
    // library and a late cleanup error must not delete them.
    void rollbackNewFiles() {
      if (committed) return;
      for (final String file in newFiles) {
        _deleteFileQuietly(File(file));
      }
    }

    Directory? staging;
    BackupResult? safety;
    try {
      onProgress?.call(
        const BackupProgress(
          fraction: 0,
          message: 'Creating a safety snapshot',
        ),
      );
      safety = await createBackup(
        settings: currentSettings,
        safetySnapshot: true,
        isCancelled: isCancelled,
        onProgress: (BackupProgress progress) {
          onProgress?.call(
            BackupProgress(
              fraction: progress.fraction == null
                  ? null
                  : progress.fraction! * 0.12,
              message: 'Safety snapshot: ${progress.message}',
            ),
          );
        },
      );

      final Directory workRoot = await _storage.backupStaging();
      staging = Directory(p.join(workRoot.path, 'restore-${newLocalId()}'));
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);

      final ExtractedBackup extracted = await BackupArchive.extract(
        preview.archivePath,
        staging,
        isCancelled: isCancelled,
        onProgress: (BackupProgress progress) {
          onProgress?.call(
            BackupProgress(
              fraction: progress.fraction == null
                  ? null
                  : 0.12 + progress.fraction! * 0.33,
              message: progress.message,
            ),
          );
        },
      );
      final Map<String, List<Map<String, Object?>>> tables = _parseDatabaseJson(
        extracted.databaseJson,
      );
      _validateCounts(extracted.manifest, tables);
      _validateRelationships(extracted.manifest, tables);

      final String settingsText = utf8.decode(extracted.settingsJson);
      _settings.decode(settingsText);

      onProgress?.call(
        const BackupProgress(
          fraction: 0.48,
          message: 'Validating records in SQLite',
        ),
      );
      final File stagingDatabase = File(p.join(staging.path, 'restore.db'));
      await _buildAndValidateStagingDatabase(stagingDatabase, tables);

      if (isCancelled?.call() == true) {
        throw const BackupCancelledException();
      }

      final Directory library = await _storage.library();
      final Directory covers = await _storage.covers();
      final Map<String, String> localPaths = <String, String>{};
      final Map<String, String> coverPaths = <String, String>{};
      final List<BackupEntry> entries = extracted.manifest.entries;
      int copyIndex = 0;
      for (final BackupEntry entry in entries) {
        if (entry.type != BackupEntryType.book &&
            entry.type != BackupEntryType.cover) {
          continue;
        }
        if (isCancelled?.call() == true) {
          throw const BackupCancelledException();
        }
        final String? sourcePath = extracted.payloadPaths[entry.path];
        if (sourcePath == null) {
          throw FormatException('The backup is missing ${entry.path}.');
        }
        final String documentId = entry.documentId!;
        final Map<String, Object?>? row = _findDocument(
          tables['documents']!,
          documentId,
        );
        if (row == null) {
          throw FormatException(
            'The backup file ${entry.path} has no matching document.',
          );
        }
        final Directory destination = entry.type == BackupEntryType.book
            ? library
            : covers;
        final String extension = _safeExtension(
          entry.type == BackupEntryType.book
              ? _databaseString(row['local_path'])
              : _databaseString(row['cover_path'] ?? ''),
        );
        String target;
        do {
          target = p.join(destination.path, '${newLocalId()}$extension');
        } while (File(target).existsSync());
        final File copied;
        try {
          copied = await File(sourcePath).copy(target);
        } on FileSystemException {
          // copy() can leave a partial destination behind; it is not yet in
          // newFiles, so remove it here before the rollback path runs.
          _deleteFileQuietly(File(target));
          rethrow;
        }
        newFiles.add(target);
        final int actualLength = await copied.length();
        final String actualHash = await _hashFile(copied);
        if (actualLength != entry.byteSize || actualHash != entry.sha256) {
          throw FormatException(
            'A file changed while it was being restored: ${entry.path}.',
          );
        }
        if (entry.type == BackupEntryType.book &&
            row['byte_size'] != actualLength) {
          throw const FormatException(
            'A document size does not match the restored book file.',
          );
        }
        if (entry.type == BackupEntryType.book) {
          localPaths[documentId] = target;
        } else {
          coverPaths[documentId] = target;
        }
        copyIndex++;
        onProgress?.call(
          BackupProgress(
            fraction: 0.52 + 0.25 * (copyIndex / entries.length),
            message: 'Copying ${entry.type.id} $copyIndex',
          ),
        );
      }

      for (final Map<String, Object?> row in tables['documents']!) {
        final String id = _databaseString(row['id']);
        final String? newPath = localPaths[id];
        if (newPath == null) {
          throw FormatException('A document has no matching book file.');
        }
        row['local_path'] = newPath;
        row['cover_path'] = coverPaths[id];
      }

      if (isCancelled?.call() == true) {
        throw const BackupCancelledException();
      }
      onProgress?.call(
        const BackupProgress(
          fraction: 0.82,
          message: 'Replacing the library database',
          cancellable: false,
        ),
      );
      final sqflite.Database live = await _database.database;
      final String? oldSettings = _settings.rawValue;
      await _settings.importJson(settingsText);
      try {
        await live.transaction((sqflite.Transaction transaction) async {
          await _replaceTables(transaction, tables);
        });
      } on Object {
        await _settings.restoreRaw(oldSettings);
        rollbackNewFiles();
        rethrow;
      }
      committed = true;

      onProgress?.call(
        const BackupProgress(
          fraction: 0.94,
          message: 'Cleaning up replaced files',
          cancellable: false,
        ),
      );
      final Set<String> referenced = <String>{
        ...localPaths.values,
        ...coverPaths.values,
      };
      await _trashUnreferenced(library, referenced);
      await _trashUnreferenced(covers, referenced);
      await _pruneSafetyBackups(safety.path);
      onProgress?.call(
        const BackupProgress(fraction: 1, message: 'Restore complete'),
      );
      return RestoreResult(
        counts: extracted.manifest.counts,
        safetySnapshotPath: safety.path,
        warnings: extracted.manifest.warnings,
      );
    } on BackupCancelledException {
      rollbackNewFiles();
      throw PaperException(
        PaperErrorKind.cancelled,
        'Restore cancelled. Your library was not changed.',
      );
    } on FormatException catch (error) {
      rollbackNewFiles();
      throw PaperException.corruptDocument(error.message, cause: error);
    } on PaperException {
      rollbackNewFiles();
      rethrow;
    } on FileSystemException catch (error) {
      rollbackNewFiles();
      throw PaperException.storage(
        'PaperOS could not restore the backup. Your previous library was '
        'left in place. Check free space and try again.',
        cause: error,
      );
    } finally {
      if (staging != null) {
        try {
          if (staging.existsSync()) await staging.delete(recursive: true);
        } on FileSystemException {
          // Staging is never part of the live library.
        }
      }
    }
  }

  Future<Map<String, List<Map<String, Object?>>>> _snapshotTables() async {
    final sqflite.Database database = await _database.database;
    return database.transaction((sqflite.Transaction transaction) async {
      final Map<String, List<Map<String, Object?>>> tables =
          <String, List<Map<String, Object?>>>{};
      for (final String table in PaperSchema.backupTables) {
        final List<Map<String, Object?>> rows = await transaction.rawQuery(
          'SELECT * FROM "$table" ORDER BY rowid',
        );
        tables[table] = rows
            .map((Map<String, Object?> row) => Map<String, Object?>.of(row))
            .toList(growable: true);
      }
      return tables;
    });
  }

  Map<String, List<Map<String, Object?>>> _parseDatabaseJson(List<int> bytes) {
    const String corrupt = 'The backup database index is corrupt.';
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const FormatException(corrupt);
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(corrupt);
    }
    if (decoded['format'] != 'paperos.database' ||
        decoded['version'] != 1 ||
        decoded['schemaVersion'] != PaperConfig.databaseVersion) {
      throw const FormatException(
        'This backup uses an unsupported database format.',
      );
    }
    final Object? rawTables = decoded['tables'];
    if (rawTables is! Map) {
      throw const FormatException(corrupt);
    }
    final Map<String, List<Map<String, Object?>>> tables =
        <String, List<Map<String, Object?>>>{};
    for (final String table in PaperSchema.backupTables) {
      final Object? rawRows = rawTables[table];
      if (rawRows is! List) {
        throw FormatException('The backup is missing the $table table.');
      }
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
      for (final Object? rawRow in rawRows) {
        if (rawRow is! Map) {
          throw FormatException('A row in $table is not an object.');
        }
        final Map<String, Object?> row = <String, Object?>{};
        for (final MapEntry<Object?, Object?> entry in rawRow.entries) {
          if (entry.key is! String) {
            throw FormatException('A column name in $table is invalid.');
          }
          row[entry.key! as String] = entry.value;
        }
        _validateRow(table, row);
        rows.add(row);
      }
      tables[table] = rows;
    }
    for (final Object? key in rawTables.keys) {
      if (!PaperSchema.backupTables.contains(key)) {
        throw FormatException('The backup contains an unknown table: $key');
      }
    }
    _validateTableRelationships(tables);
    return tables;
  }

  void _validateRow(String table, Map<String, Object?> row) {
    final List<String>? columns = PaperSchema.backupColumns[table];
    final List<String>? required = PaperSchema.requiredColumns[table];
    if (columns == null || required == null) {
      throw FormatException('The backup contains an unknown table: $table');
    }
    for (final String column in row.keys) {
      if (!columns.contains(column)) {
        throw FormatException('The backup contains an unknown $table column.');
      }
    }
    for (final String column in required) {
      if (row[column] == null) {
        throw FormatException('A $table row is missing $column.');
      }
    }
    for (final Object? value in row.values) {
      if (value is bool || value is Map || value is List) {
        throw FormatException('A $table row contains an unsupported value.');
      }
    }

    switch (table) {
      case 'documents':
        final String id = _requireText(row, 'id', table);
        _requireText(row, 'local_path', table);
        _requireText(row, 'source_name', table);
        _requireText(row, 'title', table);
        final String format = _requireText(row, 'format', table);
        if (!DocumentFormat.values.any((DocumentFormat f) => f.id == format)) {
          throw const FormatException(
            'The backup contains an unknown document format.',
          );
        }
        final String status = _requireText(row, 'status', table);
        if (!DocumentStatus.values.any((DocumentStatus s) => s.id == status)) {
          throw const FormatException(
            'The backup contains an unknown document status.',
          );
        }
        _requireInt(row, 'byte_size', table, minimum: 0);
        _requireFlag(row, 'is_favorite', table);
        _requireInt(row, 'added_at', table, minimum: 0);
        _requireInt(row, 'opened_seconds', table, minimum: 0);
        _optionalInt(row, 'page_count', table, minimum: 0);
        _optionalInt(row, 'last_page', table, minimum: -1);
        _optionalNumber(row, 'last_fraction', table, minimum: -1, maximum: 1);
        _optionalInt(row, 'max_page', table, minimum: 0);
        _optionalInt(row, 'last_opened_at', table, minimum: 0);
        for (final String text in <String>[
          'source_uri',
          'last_locator',
          'author',
          'publisher',
          'language',
          'identifier',
          'description',
          'cover_path',
          'fingerprint',
        ]) {
          _optionalText(row, text, table, allowEmpty: text == 'description');
        }
        if (id.isEmpty) {
          throw const FormatException('A document has an empty id.');
        }
      case 'bookmarks':
        _requireText(row, 'id', table);
        _requireText(row, 'document_id', table);
        _requireInt(row, 'page', table, minimum: -1);
        _requireNumber(row, 'fraction', table, minimum: -1, maximum: 1);
        _requireInt(row, 'created_at', table, minimum: 0);
        for (final String text in <String>[
          'label',
          'excerpt',
          'locator',
          'chapter_title',
        ]) {
          _optionalText(row, text, table);
        }
      case 'annotations':
        _requireText(row, 'id', table);
        _requireText(row, 'document_id', table);
        final String kind = _requireText(row, 'kind', table);
        if (!AnnotationKind.values.any((AnnotationKind k) => k.id == kind)) {
          throw const FormatException(
            'The backup contains an unknown annotation type.',
          );
        }
        _requireText(row, 'start_locator', table);
        _requireText(row, 'end_locator', table);
        _requireText(row, 'excerpt', table);
        _requireFlag(row, 'orphaned', table);
        _requireInt(row, 'created_at', table, minimum: 0);
        _requireInt(row, 'updated_at', table, minimum: 0);
        _optionalInt(row, 'chapter_index', table, minimum: 0);
        _optionalText(row, 'chapter_title', table);
        _optionalText(row, 'note', table, allowEmpty: true);
      case 'notes':
        _requireText(row, 'id', table);
        _requireText(row, 'title', table, allowEmpty: true);
        _requireText(row, 'body', table, allowEmpty: true);
        _requireInt(row, 'created_at', table, minimum: 0);
        _requireInt(row, 'updated_at', table, minimum: 0);
      case 'tasks':
        _requireText(row, 'id', table);
        _requireText(row, 'title', table);
        _requireFlag(row, 'is_done', table);
        _requireInt(row, 'created_at', table, minimum: 0);
        _optionalText(row, 'due_date', table);
        final Object? dueDate = row['due_date'];
        if (dueDate != null && (dueDate is! String || !_isDayKey(dueDate))) {
          throw const FormatException(
            'A task has an invalid due date. Expected yyyy-MM-dd.',
          );
        }
        _optionalInt(row, 'completed_at', table, minimum: 0);
      case 'locations':
        _requireText(row, 'id', table);
        _requireText(row, 'label', table);
        _requireText(row, 'path', table);
        _requireFlag(row, 'is_system', table);
        _requireInt(row, 'added_at', table, minimum: 0);
    }
  }

  void _validateTableRelationships(
    Map<String, List<Map<String, Object?>>> tables,
  ) {
    final Set<String> documentIds = <String>{};
    for (final Map<String, Object?> row in tables['documents']!) {
      final String id = _databaseString(row['id']);
      if (!documentIds.add(id)) {
        throw const FormatException('The backup has duplicate document ids.');
      }
    }
    for (final String table in <String>['bookmarks', 'annotations']) {
      final Set<String> ids = <String>{};
      for (final Map<String, Object?> row in tables[table]!) {
        if (!ids.add(_databaseString(row['id']))) {
          throw FormatException('The backup has duplicate rows in $table.');
        }
        if (!documentIds.contains(_databaseString(row['document_id']))) {
          throw FormatException(
            'A $table row refers to a document that is not in the backup.',
          );
        }
      }
    }
    for (final String table in <String>['notes', 'tasks', 'locations']) {
      final Set<String> ids = <String>{};
      for (final Map<String, Object?> row in tables[table]!) {
        if (!ids.add(_databaseString(row['id']))) {
          throw FormatException('The backup has duplicate rows in $table.');
        }
      }
    }
    final Set<String> locationPaths = <String>{};
    for (final Map<String, Object?> row in tables['locations']!) {
      if (!locationPaths.add(_databaseString(row['path']))) {
        throw const FormatException('The backup has duplicate folder paths.');
      }
    }
  }

  void _validateCounts(
    BackupManifest manifest,
    Map<String, List<Map<String, Object?>>> tables,
  ) {
    for (final String table in BackupCounts.tableNames) {
      if (manifest.counts.countFor(table) != tables[table]!.length) {
        throw FormatException(
          'The number of rows in $table does not match the backup manifest.',
        );
      }
    }
  }

  void _validateRelationships(
    BackupManifest manifest,
    Map<String, List<Map<String, Object?>>> tables,
  ) {
    final Map<String, Map<String, Object?>> documents =
        <String, Map<String, Object?>>{
          for (final Map<String, Object?> row in tables['documents']!)
            _databaseString(row['id']): row,
        };
    final Set<String> bookIds = <String>{};
    final Set<String> coverIds = <String>{};
    for (final BackupEntry entry in manifest.entries) {
      final String? documentId = entry.documentId;
      if (entry.type == BackupEntryType.book) {
        if (documentId == null || !documents.containsKey(documentId)) {
          throw const FormatException(
            'A book file has no matching document in the backup.',
          );
        }
        if (!bookIds.add(documentId)) {
          throw const FormatException(
            'A document in the backup has more than one book file.',
          );
        }
      } else if (entry.type == BackupEntryType.cover) {
        if (documentId == null || !documents.containsKey(documentId)) {
          throw const FormatException(
            'A cover file has no matching document in the backup.',
          );
        }
        if (!coverIds.add(documentId)) {
          throw const FormatException(
            'A document in the backup has more than one cover file.',
          );
        }
      }
    }
    for (final MapEntry<String, Map<String, Object?>> item
        in documents.entries) {
      if (!bookIds.contains(item.key)) {
        throw const FormatException(
          'A document in the backup is missing its book file.',
        );
      }
      final String? cover = item.value['cover_path'] as String?;
      if (cover != null && cover.isNotEmpty && !coverIds.contains(item.key)) {
        throw const FormatException(
          'A document in the backup is missing its cover file.',
        );
      }
      if ((cover == null || cover.isEmpty) && coverIds.contains(item.key)) {
        throw const FormatException(
          'The backup contains an unexpected cover file.',
        );
      }
    }
  }

  Future<void> _buildAndValidateStagingDatabase(
    File path,
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    if (path.existsSync()) path.deleteSync();
    final sqflite.Database staging = await _factory.openDatabase(
      path.path,
      options: sqflite.OpenDatabaseOptions(
        version: PaperConfig.databaseVersion,
        singleInstance: false,
        onConfigure: (sqflite.Database database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (sqflite.Database database, int version) =>
            AppDatabaseOpener.createSchema(database),
      ),
    );
    try {
      await staging.transaction((sqflite.Transaction transaction) async {
        for (final String table in PaperSchema.backupTables) {
          for (final Map<String, Object?> row in tables[table]!) {
            await transaction.insert(table, row);
          }
        }
        final List<Map<String, Object?>> foreignKeys = await transaction
            .rawQuery('PRAGMA foreign_key_check');
        if (foreignKeys.isNotEmpty) {
          throw const FormatException(
            'The backup contains broken relationships between records.',
          );
        }
        for (final String table in PaperSchema.backupTables) {
          final int? count = sqflite.Sqflite.firstIntValue(
            await transaction.rawQuery('SELECT COUNT(*) FROM "$table"'),
          );
          if (count != tables[table]!.length) {
            throw FormatException('The backup $table table did not validate.');
          }
        }
      });
    } on sqflite.DatabaseException catch (error) {
      throw FormatException(
        'The backup records are not valid for the PaperOS database: '
        '${error.toString()}',
      );
    } finally {
      await staging.close();
    }

    final sqflite.Database check = await _factory.openDatabase(
      path.path,
      options: sqflite.OpenDatabaseOptions(
        readOnly: true,
        singleInstance: false,
      ),
    );
    try {
      final List<Map<String, Object?>> integrity = await check.rawQuery(
        'PRAGMA integrity_check',
      );
      if (integrity.length != 1 || integrity.first.values.first != 'ok') {
        throw const FormatException(
          'The restored database failed its SQLite integrity check.',
        );
      }
      final List<Map<String, Object?>> foreignKeys = await check.rawQuery(
        'PRAGMA foreign_key_check',
      );
      if (foreignKeys.isNotEmpty) {
        throw const FormatException(
          'The restored database contains broken relationships.',
        );
      }
      final int version =
          sqflite.Sqflite.firstIntValue(
            await check.rawQuery('PRAGMA user_version'),
          ) ??
          -1;
      if (version != PaperConfig.databaseVersion) {
        throw const FormatException(
          'The restored database has the wrong schema version.',
        );
      }
    } finally {
      await check.close();
    }
  }

  Future<void> _replaceTables(
    sqflite.Transaction transaction,
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    for (final String table in PaperSchema.backupTables.reversed) {
      await transaction.delete(table);
    }
    for (final String table in PaperSchema.backupTables) {
      for (final Map<String, Object?> row in tables[table]!) {
        await transaction.insert(table, row);
      }
      final int? count = sqflite.Sqflite.firstIntValue(
        await transaction.rawQuery('SELECT COUNT(*) FROM "$table"'),
      );
      if (count != tables[table]!.length) {
        throw FormatException('The restored $table table is incomplete.');
      }
    }
    final List<Map<String, Object?>> foreignKeys = await transaction.rawQuery(
      'PRAGMA foreign_key_check',
    );
    if (foreignKeys.isNotEmpty) {
      throw const FormatException(
        'The restored records contain broken relationships.',
      );
    }
  }

  Future<void> _trashUnreferenced(
    Directory directory,
    Set<String> referenced,
  ) async {
    try {
      await for (final FileSystemEntity entity in directory.list()) {
        if (entity is! File) continue;
        if (referenced.contains(entity.path)) continue;
        try {
          await _storage.trashFile(entity.path);
        } on FileSystemException {
          // The restore is already committed; a leftover file is harmless.
        }
      }
    } on FileSystemException {
      // Cleanup is best effort and never rolls back a valid restore.
    }
  }

  Future<void> _pruneSafetyBackups(String keepPath) async {
    try {
      final Directory directory = await _storage.safetyBackups();
      final List<File> files = <File>[];
      await for (final FileSystemEntity entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.paperosbackup')) {
          files.add(entity);
        }
      }
      files.sort((File a, File b) {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      });
      int kept = 0;
      for (final File file in files) {
        kept++;
        if (kept > PaperConfig.maxSafetyBackups && file.path != keepPath) {
          _deleteFileQuietly(file);
        }
      }
    } on FileSystemException {
      // Retention failure must never fail a successful restore.
    }
  }

  Map<String, Object?>? _findDocument(
    List<Map<String, Object?>> documents,
    String id,
  ) {
    for (final Map<String, Object?> row in documents) {
      if (row['id'] == id) return row;
    }
    return null;
  }
}

class _SourceFile {
  const _SourceFile({
    required this.documentId,
    required this.file,
    required this.archivePath,
    required this.kind,
  });

  final String documentId;
  final File file;
  final String archivePath;
  final String kind;
}

String _hashBytes(List<int> bytes) => crypto.sha256.convert(bytes).toString();

Future<String> _hashFile(File file) async {
  final crypto.Digest digest = await crypto.sha256.bind(file.openRead()).first;
  return digest.toString();
}

String _safeExtension(String path) {
  final String extension = p.extension(path).toLowerCase();
  if (RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)) return extension;
  return '.bin';
}

bool _isInside(String root, String path) {
  if (path.isEmpty) return false;
  return p.isWithin(
    p.normalize(p.absolute(root)),
    p.normalize(p.absolute(path)),
  );
}

String _databaseString(Object? value) {
  if (value is String) return value;
  throw const FormatException('A record in the library is corrupt.');
}

String _requireText(
  Map<String, Object?> row,
  String key,
  String table, {
  bool allowEmpty = false,
}) {
  final Object? value = row[key];
  if (value is! String || (!allowEmpty && value.isEmpty)) {
    throw FormatException('A $table record has an invalid $key.');
  }
  return value;
}

String? _optionalText(
  Map<String, Object?> row,
  String key,
  String table, {
  bool allowEmpty = true,
}) {
  final Object? value = row[key];
  if (value == null) return null;
  if (value is! String || (!allowEmpty && value.isEmpty)) {
    throw FormatException('A $table record has an invalid $key.');
  }
  return value;
}

int _requireInt(
  Map<String, Object?> row,
  String key,
  String table, {
  int? minimum,
  int? maximum,
}) {
  final Object? value = row[key];
  if (value is! int) {
    throw FormatException('A $table record has an invalid $key.');
  }
  if (minimum != null && value < minimum ||
      maximum != null && value > maximum) {
    throw FormatException('A $table record has an out-of-range $key.');
  }
  return value;
}

int? _optionalInt(
  Map<String, Object?> row,
  String key,
  String table, {
  int? minimum,
  int? maximum,
}) {
  if (row[key] == null) return null;
  return _requireInt(row, key, table, minimum: minimum, maximum: maximum);
}

num _requireNumber(
  Map<String, Object?> row,
  String key,
  String table, {
  num? minimum,
  num? maximum,
}) {
  final Object? value = row[key];
  if (value is! num) {
    throw FormatException('A $table record has an invalid $key.');
  }
  if (minimum != null && value < minimum ||
      maximum != null && value > maximum) {
    throw FormatException('A $table record has an out-of-range $key.');
  }
  return value;
}

num? _optionalNumber(
  Map<String, Object?> row,
  String key,
  String table, {
  num? minimum,
  num? maximum,
}) {
  if (row[key] == null) return null;
  return _requireNumber(row, key, table, minimum: minimum, maximum: maximum);
}

void _requireFlag(Map<String, Object?> row, String key, String table) {
  final int value = _requireInt(row, key, table);
  if (value != 0 && value != 1) {
    throw FormatException('A $table record has an invalid $key flag.');
  }
}

/// True for a real calendar day in the `yyyy-MM-dd` form used by tasks.
/// A round-trip rejects values such as `2026-02-31` that [DateTime] would
/// otherwise normalise into March.
bool _isDayKey(String value) {
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null) return false;
  String two(int part) => part.toString().padLeft(2, '0');
  return '${parsed.year.toString().padLeft(4, '0')}-'
          '${two(parsed.month)}-${two(parsed.day)}' ==
      value;
}

String _fileStamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}${two(time.minute)}${two(time.second)}';
}

void _deleteFileQuietly(File file) {
  try {
    if (file.existsSync()) file.deleteSync();
  } on FileSystemException {
    // Caller is already reporting a failure; a stray file is disposable.
  }
}
