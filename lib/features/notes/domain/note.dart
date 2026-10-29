import 'package:flutter/foundation.dart';

/// A plain local note. No rich text, no blocks, no sync.
@immutable
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The title, or a derived fallback so a list row is never blank.
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final String firstLine = body
        .trim()
        .split('\n')
        .firstWhere((String line) => line.trim().isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return 'Untitled note';
    return firstLine.length <= 60
        ? firstLine
        : '${firstLine.substring(0, 59)}…';
  }

  /// First line of the body, or empty when the note is only a title.
  String get preview {
    final String trimmed = body.trim();
    if (trimmed.isEmpty) return '';
    final String firstLine = trimmed.split('\n').first;
    return firstLine.length <= 120
        ? firstLine
        : '${firstLine.substring(0, 119)}…';
  }

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  int get wordCount {
    final String trimmed = body.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  Note copyWith({String? title, String? body, DateTime? updatedAt}) {
    return Note(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) => other is Note && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
