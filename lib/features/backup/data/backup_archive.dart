import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../../../config/app_config.dart';
import '../domain/backup_manifest.dart';

/// Thrown when restoring must stop because the user asked to cancel.
class BackupCancelledException implements Exception {
  const BackupCancelledException();
}

/// A fully extracted, checksum-verified archive in private staging storage.
class ExtractedBackup {
  const ExtractedBackup({
    required this.manifest,
    required this.stagingDirectory,
    required this.databaseJson,
    required this.settingsJson,
    required this.payloadPaths,
  });

  final BackupManifest manifest;
  final Directory stagingDirectory;
  final List<int> databaseJson;
  final List<int> settingsJson;

  /// Archive path to the extracted file on disk.
  final Map<String, String> payloadPaths;
}

/// Reads and writes the ZIP container around the backup domain model.
///
/// Archives are untrusted. The central directory is inspected before a single
/// byte is decompressed: duplicate names, unsafe paths, encrypted entries,
/// symlinks, unsupported compression, impossible sizes and excessive entry
/// counts are all rejected. Payload SHA-256 values from the signed manifest are
/// checked while the bytes stream to staging; no book is ever held in memory.
abstract final class BackupArchive {
  /// Reads and validates the manifest and container structure without writing
  /// any payload. Used for the pre-restore preview.
  static Future<BackupManifest> inspect(String archivePath) async {
    final _ArchiveSession session = _open(archivePath);
    try {
      final BackupManifest manifest = _readManifest(session);
      _validateManifestEntries(session, manifest);
      return manifest;
    } finally {
      session.close();
    }
  }

  /// Verifies and extracts every payload into [staging].
  static Future<ExtractedBackup> extract(
    String archivePath,
    Directory staging, {
    void Function(BackupProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final _ArchiveSession session = _open(archivePath);
    try {
      final BackupManifest manifest = _readManifest(session);
      _validateManifestEntries(session, manifest);
      if (manifest.counts.documents > PaperConfig.maxBackupDocuments) {
        throw FormatException(
          'This backup contains more than '
          '${PaperConfig.maxBackupDocuments} documents.',
        );
      }
      if (!staging.existsSync()) {
        await staging.create(recursive: true);
      }
      final Map<String, String> payloadPaths = <String, String>{};
      final List<BackupEntry> entries = manifest.entries;
      for (int i = 0; i < entries.length; i++) {
        if (isCancelled?.call() == true) {
          throw const BackupCancelledException();
        }
        final BackupEntry entry = entries[i];
        final ZipFileHeader header = session.headers[entry.path]!;
        if (header.uncompressedSize != entry.byteSize) {
          throw FormatException(
            'The size of ${entry.path} does not match the manifest.',
          );
        }
        final File target = _stagingTarget(staging, entry);
        final Directory parent = target.parent;
        if (!parent.existsSync()) parent.createSync(recursive: true);
        if (target.existsSync()) {
          throw FormatException('Duplicate restored file ${entry.path}.');
        }
        final OutputFileStream output = OutputFileStream(target.path);
        try {
          header.file!.decompress(output);
        } catch (error) {
          await output.close();
          _deleteQuietly(target);
          if (error is FormatException || error is BackupCancelledException) {
            rethrow;
          }
          throw FormatException('Could not read ${entry.path} from the backup.');
        }
        await output.close();
        final int actualLength = await target.length();
        if (actualLength != entry.byteSize) {
          _deleteQuietly(target);
          throw FormatException(
            'The size of ${entry.path} does not match the manifest.',
          );
        }
        final String actualHash = await _hashFile(target);
        if (actualHash != entry.sha256) {
          _deleteQuietly(target);
          throw FormatException('Checksum mismatch for ${entry.path}.');
        }
        payloadPaths[entry.path] = target.path;
        onProgress?.call(
          BackupProgress(
            fraction: (i + 1) / (entries.length + 1),
            message: 'Checking ${entry.type.id} ${i + 1} of ${entries.length}',
          ),
        );
      }

      final File database = File('${staging.path}${Platform.pathSeparator}database.json');
      final File settings = File('${staging.path}${Platform.pathSeparator}settings.json');
      final List<int> databaseBytes = await _readBounded(database, PaperConfig.maxBackupJsonBytes);
      final List<int> settingsBytes = await _readBounded(settings, PaperConfig.maxBackupJsonBytes);
      onProgress?.call(
        const BackupProgress(fraction: 1, message: 'Backup verified'),
      );
      return ExtractedBackup(
        manifest: manifest,
        stagingDirectory: staging,
        databaseJson: databaseBytes,
        settingsJson: settingsBytes,
        payloadPaths: payloadPaths,
      );
    } finally {
      session.close();
    }
  }

  static _ArchiveSession _open(String archivePath) {
    final File file = File(archivePath);
    if (!file.existsSync()) {
      throw const FormatException('That backup file is no longer available.');
    }
    final int archiveLength = file.lengthSync();
    if (archiveLength < 32 || archiveLength > PaperConfig.maxBackupUncompressedBytes) {
      throw const FormatException('That file is not a valid PaperOS backup.');
    }
    final InputFileStream input = InputFileStream(archivePath);
    try {
      final ZipDirectory directory = ZipDirectory();
      try {
        directory.read(input);
      } on Object {
        throw const FormatException('That file is not a valid ZIP archive.');
      }
      if (directory.fileHeaders.isEmpty) {
        throw const FormatException('That ZIP archive is empty.');
      }
      if (directory.totalCentralDirectoryEntries != directory.fileHeaders.length ||
          directory.totalCentralDirectoryEntriesOnThisDisk != directory.fileHeaders.length ||
          directory.numberOfThisDisk != 0) {
        throw const FormatException('The backup ZIP directory is inconsistent.');
      }
      if (directory.fileHeaders.length > PaperConfig.maxBackupEntries) {
        throw FormatException(
          'This backup has more than ${PaperConfig.maxBackupEntries} files.',
        );
      }

      final Map<String, ZipFileHeader> headers = <String, ZipFileHeader>{};
      int totalBytes = 0;
      int compressedBytes = 0;
      for (final ZipFileHeader header in directory.fileHeaders) {
        _checkPath(header.filename);
        if (!headers.containsKey(header.filename)) {
          headers[header.filename] = header;
        } else {
          throw FormatException('Duplicate file in backup: ${header.filename}');
        }
        if (header.generalPurposeBitFlag & 0x1 != 0) {
          throw const FormatException(
            'Encrypted backups are not supported by this version of PaperOS.',
          );
        }
        if (header.compressionMethod != 0 && header.compressionMethod != 8) {
          throw const FormatException(
            'The backup uses an unsupported compression method.',
          );
        }
        if (header.versionMadeBy >> 8 == 3 &&
            (header.externalFileAttributes >> 16) & 0xf000 == 0xa000) {
          throw const FormatException('The backup contains a symbolic link.');
        }
        if (header.filename.endsWith('/') ||
            header.filename.endsWith('\\') ||
            header.file == null) {
          throw const FormatException('The backup contains a directory entry.');
        }
        if (header.uncompressedSize < 0 ||
            header.uncompressedSize > PaperConfig.maxBackupEntryBytes) {
          throw FormatException(
            'The backup contains a file that is too large: ${header.filename}',
          );
        }
        totalBytes += header.uncompressedSize;
        compressedBytes += header.compressedSize;
        if (totalBytes > PaperConfig.maxBackupUncompressedBytes ||
            compressedBytes > archiveLength) {
          throw const FormatException(
            'The backup expands to more data than PaperOS will restore.',
          );
        }
      }
      return _ArchiveSession(input, directory, headers);
    } catch (error) {
      input.closeSync();
      if (error is FormatException) rethrow;
      throw const FormatException('That file is not a valid PaperOS backup.');
    }
  }

  static BackupManifest _readManifest(_ArchiveSession session) {
    final ZipFileHeader? manifestHeader = session.headers['manifest.json'];
    final ZipFileHeader? checksumHeader = session.headers['manifest.sha256'];
    if (manifestHeader == null || checksumHeader == null) {
      throw const FormatException('This ZIP is not a PaperOS backup.');
    }
    if (manifestHeader.uncompressedSize > PaperConfig.maxBackupManifestBytes ||
        checksumHeader.uncompressedSize > 1024) {
      throw const FormatException('The backup manifest is too large.');
    }
    final List<int> manifestBytes = _readEntry(manifestHeader, PaperConfig.maxBackupManifestBytes);
    final List<int> checksumBytes = _readEntry(checksumHeader, 1024);
    final String checksumText;
    try {
      checksumText = utf8.decode(checksumBytes).trim();
    } on FormatException {
      throw const FormatException('The backup checksum file is corrupt.');
    }
    final RegExpMatch? match = RegExp(
      r'^([a-fA-F0-9]{64})(?:\s+\*?manifest\.json)?\s*$',
    ).firstMatch(checksumText);
    if (match == null) {
      throw const FormatException('The backup checksum file is corrupt.');
    }
    final String actual = crypto.sha256.convert(manifestBytes).toString();
    if (actual != match.group(1)!.toLowerCase()) {
      throw const FormatException(
        'The backup manifest failed its checksum. The file is damaged or was changed.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(manifestBytes));
    } on FormatException {
      throw const FormatException('The backup manifest is not valid JSON.');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('The backup manifest is not an object.');
    }
    return BackupManifest.fromJson(decoded);
  }

  static void _validateManifestEntries(
    _ArchiveSession session,
    BackupManifest manifest,
  ) {
    if (manifest.schemaVersion > PaperConfig.databaseVersion) {
      throw FormatException(
        'This backup uses database schema ${manifest.schemaVersion}, but this '
        'version of PaperOS supports ${PaperConfig.databaseVersion}. '
        'Update PaperOS before restoring it.',
      );
    }
    if (manifest.schemaVersion != PaperConfig.databaseVersion) {
      throw FormatException(
        'This backup uses an unsupported database schema '
        '(${manifest.schemaVersion}).',
      );
    }

    const Set<String> metaPaths = <String>{'database.json', 'settings.json'};
    final Set<String> manifestPaths = <String>{
      'manifest.json',
      'manifest.sha256',
    };
    final Set<String> seen = <String>{};
    int databaseEntries = 0;
    int settingsEntries = 0;
    int libraryBytes = 0;
    for (final BackupEntry entry in manifest.entries) {
      if (!seen.add(entry.path)) {
        throw FormatException('Duplicate file in backup: ${entry.path}');
      }
      final ZipFileHeader? header = session.headers[entry.path];
      if (header == null) {
        throw FormatException('The backup is missing ${entry.path}.');
      }
      if (header.uncompressedSize != entry.byteSize) {
        throw FormatException(
          'The manifest size of ${entry.path} is incorrect.',
        );
      }
      switch (entry.type) {
        case BackupEntryType.database:
          if (entry.path != 'database.json' || databaseEntries++ > 0) {
            throw const FormatException('The backup database entry is invalid.');
          }
        case BackupEntryType.settings:
          if (entry.path != 'settings.json' || settingsEntries++ > 0) {
            throw const FormatException('The backup settings entry is invalid.');
          }
        case BackupEntryType.book:
          if (!_isFlatEntry(entry.path, 'books/')) {
            throw const FormatException('The backup has a misplaced book file.');
          }
          libraryBytes += entry.byteSize;
        case BackupEntryType.cover:
          if (!_isFlatEntry(entry.path, 'covers/')) {
            throw const FormatException(
              'The backup has a misplaced cover file.',
            );
          }
          libraryBytes += entry.byteSize;
      }
    }
    if (databaseEntries != 1 || settingsEntries != 1) {
      throw const FormatException(
        'The backup is missing its database or settings file.',
      );
    }
    if (libraryBytes != manifest.libraryBytes) {
      throw const FormatException('The backup library size is inconsistent.');
    }
    for (final String path in session.headers.keys) {
      if (manifestPaths.contains(path)) continue;
      if (!seen.contains(path)) {
        throw FormatException('Unexpected file in backup: $path');
      }
    }
    // The metadata paths are part of the payload list, never extra entries.
    for (final String path in metaPaths) {
      if (!seen.contains(path)) {
        throw FormatException('The backup is missing $path.');
      }
    }
  }

  static bool _isFlatEntry(String path, String prefix) {
    if (!path.startsWith(prefix)) return false;
    final String rest = path.substring(prefix.length);
    return rest.isNotEmpty && !rest.contains('/') && !rest.contains('..');
  }

  static List<int> _readEntry(ZipFileHeader header, int maxBytes) {
    final OutputMemoryStream output = OutputMemoryStream();
    try {
      header.file!.decompress(output);
      if (output.length > maxBytes) {
        throw const FormatException('A metadata file in the backup is too large.');
      }
      return output.getBytes().toList(growable: false);
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('The backup contains an unreadable file.');
    }
  }

  static Future<String> _hashFile(File file) async {
    final crypto.Digest digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  static Future<List<int>> _readBounded(File file, int maxBytes) async {
    final int length = await file.length();
    if (length > maxBytes) {
      throw const FormatException('A backup data file is too large.');
    }
    return file.readAsBytes();
  }

  static File _stagingTarget(Directory staging, BackupEntry entry) {
    // The path has already been checked. Map the archive path to a flat pair of
    // staging folders; never let an archive name become an OS path directly.
    final String name = p.basename(entry.path);
    final String folder = switch (entry.type) {
      BackupEntryType.database || BackupEntryType.settings => '',
      BackupEntryType.book => 'books',
      BackupEntryType.cover => 'covers',
    };
    return File(
      p.joinAll(<String>[staging.path, if (folder.isNotEmpty) folder, name]),
    );
  }

  static void _checkPath(String path) {
    if (path.isEmpty ||
        path.length > 200 ||
        path.startsWith('/') ||
        path.startsWith('\\') ||
        path.contains('\\') ||
        path.contains('\u0000') ||
        path.contains(':')) {
      throw const FormatException('The backup contains an unsafe file path.');
    }
    final List<String> segments = path.split('/');
    if (segments.isEmpty ||
        segments.any(
          (String segment) =>
              segment.isEmpty ||
              segment == '.' ||
              segment == '..' ||
              !RegExp(r'^[A-Za-z0-9._ -]+$').hasMatch(segment),
        )) {
      throw const FormatException('The backup contains an unsafe file path.');
    }
  }

  static void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // The caller is already failing; a stray staging file is disposable.
    }
  }
}

class _ArchiveSession {
  _ArchiveSession(this.input, this.directory, this.headers);

  final InputFileStream input;
  final ZipDirectory directory;
  final Map<String, ZipFileHeader> headers;

  void close() {
    try {
      input.closeSync();
    } on Object {
      // The OS handle is already unusable; nothing else to release.
    }
  }
}


