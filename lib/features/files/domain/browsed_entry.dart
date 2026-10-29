import 'package:flutter/foundation.dart';

import '../../library/domain/document.dart';

/// A folder the user granted PaperOS long-term read access to.
///
/// [uri] is the Storage Access Framework *tree* uri (`content://.../tree/...`)
/// the platform issued when the folder was picked. PaperOS stores it and hands
/// it back to the OS to list and to read; it never tries to turn it into a
/// filesystem path, because on Android 11+ there is no such path.
@immutable
class BrowsedLocation {
  const BrowsedLocation({
    required this.id,
    required this.uri,
    required this.label,
  });

  /// Row id in the `locations` table.
  final String id;

  /// The persisted tree uri.
  final String uri;

  /// Display name, usually the folder's own name.
  final String label;

  @override
  bool operator ==(Object other) => other is BrowsedLocation && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// One child of a location (or of any folder inside it).
@immutable
class BrowsedEntry {
  const BrowsedEntry({
    required this.uri,
    required this.name,
    required this.isDirectory,
    this.mimeType,
    this.byteSize,
    this.lastModified,
  });

  /// The document uri, not the tree uri. This is what is passed back to the
  /// platform to read the file.
  final String uri;

  final String name;
  final bool isDirectory;
  final String? mimeType;
  final int? byteSize;
  final DateTime? lastModified;

  /// What PaperOS thinks this entry is, from its name.
  DocumentFormat get format =>
      isDirectory ? DocumentFormat.unknown : DocumentFormat.fromFileName(name);

  /// Whether the reader can currently open this entry.
  bool get isReadable => !isDirectory && DocumentFormat.isReadable(format);

  factory BrowsedEntry.fromMap(Map<Object?, Object?> map) {
    final int? size = (map['byteSize'] as num?)?.toInt();
    final int? modified = (map['lastModified'] as num?)?.toInt();
    return BrowsedEntry(
      uri: map['uri']! as String,
      name: (map['name'] as String?) ?? 'Unnamed',
      isDirectory: (map['isDirectory'] as bool?) ?? false,
      mimeType: map['mimeType'] as String?,
      byteSize: size,
      lastModified: modified == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(modified),
    );
  }
}

/// A document another app asked PaperOS to open via an `ACTION_VIEW` intent.
@immutable
class ExternalDocument {
  const ExternalDocument({required this.uri, this.name, this.mimeType});

  final String uri;
  final String? name;
  final String? mimeType;

  factory ExternalDocument.fromMap(Map<Object?, Object?> map) =>
      ExternalDocument(
        uri: map['uri']! as String,
        name: map['name'] as String?,
        mimeType: map['mimeType'] as String?,
      );
}
