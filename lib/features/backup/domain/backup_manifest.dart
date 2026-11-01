import '../../../config/app_config.dart';

/// A file inside a `.paperosbackup` archive.
enum BackupEntryType {
  database('database'),
  settings('settings'),
  book('book'),
  cover('cover');

  const BackupEntryType(this.id);

  final String id;

  static BackupEntryType? tryParse(String? id) {
    for (final BackupEntryType type in BackupEntryType.values) {
      if (type.id == id) return type;
    }
    return null;
  }
}

/// One payload entry and the checksum that authenticates it.
class BackupEntry {
  const BackupEntry({
    required this.path,
    required this.type,
    required this.byteSize,
    required this.sha256,
    this.documentId,
  });

  final String path;
  final BackupEntryType type;
  final int byteSize;
  final String sha256;

  /// Present for books and covers, linking the file to a row in `documents`.
  final String? documentId;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'type': type.id,
    'bytes': byteSize,
    'sha256': sha256,
    if (documentId != null) 'documentId': documentId,
  };

  static BackupEntry fromJson(Map<String, Object?> json) {
    final String? path = _string(json['path']);
    final BackupEntryType? type = BackupEntryType.tryParse(
      _string(json['type']),
    );
    final int? byteSize = _int(json['bytes']);
    final String? sha256 = _string(json['sha256']);
    final String? documentId = _string(json['documentId']);
    if (path == null || path.isEmpty) {
      throw const FormatException('Backup entry has no path.');
    }
    if (type == null) {
      throw FormatException('Backup entry "$path" has an unknown type.');
    }
    if (byteSize == null || byteSize < 0) {
      throw FormatException('Backup entry "$path" has an invalid size.');
    }
    if (sha256 == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw FormatException('Backup entry "$path" has an invalid checksum.');
    }
    if ((type == BackupEntryType.book || type == BackupEntryType.cover) &&
        (documentId == null || documentId.isEmpty)) {
      throw FormatException('Backup entry "$path" has no document id.');
    }
    return BackupEntry(
      path: path,
      type: type,
      byteSize: byteSize,
      sha256: sha256,
      documentId: documentId,
    );
  }
}

/// Counts shown before a restore and compared again after it.
class BackupCounts {
  const BackupCounts({
    required this.documents,
    required this.bookmarks,
    required this.annotations,
    required this.notes,
    required this.tasks,
    required this.locations,
  });

  final int documents;
  final int bookmarks;
  final int annotations;
  final int notes;
  final int tasks;
  final int locations;

  static const List<String> tableNames = <String>[
    'documents',
    'bookmarks',
    'annotations',
    'notes',
    'tasks',
    'locations',
  ];

  static BackupCounts fromTables(Map<String, List<Map<String, Object?>>> tables) {
    return BackupCounts(
      documents: tables['documents']?.length ?? 0,
      bookmarks: tables['bookmarks']?.length ?? 0,
      annotations: tables['annotations']?.length ?? 0,
      notes: tables['notes']?.length ?? 0,
      tasks: tables['tasks']?.length ?? 0,
      locations: tables['locations']?.length ?? 0,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'documents': documents,
    'bookmarks': bookmarks,
    'annotations': annotations,
    'notes': notes,
    'tasks': tasks,
    'locations': locations,
  };

  int countFor(String table) => switch (table) {
    'documents' => documents,
    'bookmarks' => bookmarks,
    'annotations' => annotations,
    'notes' => notes,
    'tasks' => tasks,
    'locations' => locations,
    _ => -1,
  };

  static BackupCounts fromJson(Map<String, Object?> json) {
    int read(String key) {
      final Object? value = json[key];
      if (value is! int || value < 0) {
        throw FormatException('Backup count "$key" is invalid.');
      }
      return value;
    }

    return BackupCounts(
      documents: read('documents'),
      bookmarks: read('bookmarks'),
      annotations: read('annotations'),
      notes: read('notes'),
      tasks: read('tasks'),
      locations: read('locations'),
    );
  }
}

/// The signed index of a PaperOS backup.
class BackupManifest {
  const BackupManifest({
    required this.format,
    required this.version,
    required this.appVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.counts,
    required this.entries,
    required this.libraryBytes,
    required this.warnings,
  });

  final String format;
  final int version;
  final String appVersion;
  final int schemaVersion;
  final DateTime createdAt;
  final BackupCounts counts;
  final List<BackupEntry> entries;
  final int libraryBytes;
  final List<String> warnings;

  BackupEntry? entryFor(String path) {
    for (final BackupEntry entry in entries) {
      if (entry.path == path) return entry;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'format': format,
    'version': version,
    'appVersion': appVersion,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'counts': counts.toJson(),
    'libraryBytes': libraryBytes,
    'entries': <Object?>[for (final BackupEntry entry in entries) entry.toJson()],
    'warnings': warnings,
  };

  static BackupManifest fromJson(Map<String, Object?> json) {
    final String? format = _string(json['format']);
    if (format != PaperConfig.backupFormat) {
      throw const FormatException('This is not a PaperOS backup.');
    }
    final int? version = _int(json['version']);
    if (version == null) {
      throw const FormatException('The backup has no format version.');
    }
    if (version > PaperConfig.backupFormatVersion) {
      throw FormatException(
        'This backup was made by a newer version of PaperOS '
        '(format $version). Update PaperOS before restoring it.',
      );
    }
    if (version < 1) {
      throw FormatException('Unsupported backup format version $version.');
    }
    final String? appVersion = _string(json['appVersion']);
    final int? schemaVersion = _int(json['schemaVersion']);
    final String? created = _string(json['createdAt']);
    final DateTime? createdAt = created == null
        ? null
        : DateTime.tryParse(created);
    if (appVersion == null || appVersion.isEmpty) {
      throw const FormatException('The backup has no app version.');
    }
    if (schemaVersion == null || schemaVersion < 1) {
      throw const FormatException('The backup has no schema version.');
    }
    if (createdAt == null) {
      throw const FormatException('The backup has no creation date.');
    }
    final Map<String, Object?>? countsJson = _map(json['counts']);
    if (countsJson == null) {
      throw const FormatException('The backup has no row counts.');
    }
    final BackupCounts counts = BackupCounts.fromJson(countsJson);
    final List<Object?>? rawEntries = json['entries'] as List<Object?>?;
    if (rawEntries == null) {
      throw const FormatException('The backup has no file list.');
    }
    final List<BackupEntry> entries = <BackupEntry>[];
    final Set<String> paths = <String>{};
    for (final Object? raw in rawEntries) {
      final Map<String, Object?>? map = _map(raw);
      if (map == null) {
        throw const FormatException('A backup file entry is not an object.');
      }
      final BackupEntry entry = BackupEntry.fromJson(map);
      if (!paths.add(entry.path)) {
        throw FormatException('Duplicate file in backup: ${entry.path}');
      }
      entries.add(entry);
    }
    final int? libraryBytes = _int(json['libraryBytes']);
    if (libraryBytes == null || libraryBytes < 0) {
      throw const FormatException('The backup has an invalid library size.');
    }
    final List<Object?> warningsRaw =
        (json['warnings'] as List<Object?>?) ?? const <Object?>[];
    final List<String> warnings = <String>[];
    for (final Object? raw in warningsRaw) {
      if (raw is! String) {
        throw const FormatException('A backup warning is not text.');
      }
      warnings.add(raw);
    }
    return BackupManifest(
      format: format!,
      version: version,
      appVersion: appVersion,
      schemaVersion: schemaVersion,
      createdAt: createdAt,
      counts: counts,
      entries: List<BackupEntry>.unmodifiable(entries),
      libraryBytes: libraryBytes,
      warnings: List<String>.unmodifiable(warnings),
    );
  }
}

/// An inspected, structurally valid archive. This is not yet permission to
/// restore: [BackupService.restore] validates and extracts every payload again.
class BackupPreview {
  const BackupPreview({
    required this.archivePath,
    required this.displayName,
    required this.archiveBytes,
    required this.manifest,
  });

  final String archivePath;
  final String displayName;
  final int archiveBytes;
  final BackupManifest manifest;
}

/// Progress for either direction. [fraction] is 0..1, or null while the
/// database transaction is doing work with no useful granularity.
class BackupProgress {
  const BackupProgress({
    required this.fraction,
    required this.message,
    this.cancellable = true,
  });

  final double? fraction;
  final String message;
  final bool cancellable;
}

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  return null;
}

Map<String, Object?>? _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return null;
}
