import 'package:flutter/foundation.dart';

/// The three annotation kinds PaperOS supports on reflowable text.
///
/// PDF annotations are deliberately absent from v1.1: the native PDF renderer
/// returns a bitmap, so offering text highlights there would be a claim the
/// implementation cannot keep.
enum AnnotationKind {
  highlight('highlight', 'Highlight'),
  underline('underline', 'Underline'),
  note('note', 'Note');

  const AnnotationKind(this.id, this.label);

  final String id;
  final String label;

  static AnnotationKind parse(String id) {
    for (final AnnotationKind kind in AnnotationKind.values) {
      if (kind.id == id) return kind;
    }
    return AnnotationKind.highlight;
  }
}

/// A highlight, underline or attached note.
///
/// The two locators are format-native anchors. For EPUB they are
/// `epub:spine=<index>;char=<offset>` values, where the character offset is
/// relative to the chapter's extracted text. They do not depend on the page
/// size, font, line height or margins used to render the book.
@immutable
class Annotation {
  const Annotation({
    required this.id,
    required this.documentId,
    required this.kind,
    required this.startLocator,
    required this.endLocator,
    required this.excerpt,
    required this.createdAt,
    required this.updatedAt,
    this.chapterIndex,
    this.chapterTitle,
    this.note,
    this.orphaned = false,
  });

  final String id;
  final String documentId;
  final AnnotationKind kind;
  final String startLocator;
  final String endLocator;
  final String excerpt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? chapterIndex;
  final String? chapterTitle;
  final String? note;

  /// True when this build cannot resolve the stored anchor. The row and note
  /// are kept, and the annotation library offers the excerpt and a delete
  /// action instead of silently losing the user's work.
  final bool orphaned;

  bool get hasNote => note?.trim().isNotEmpty == true;

  Annotation copyWith({
    AnnotationKind? kind,
    String? startLocator,
    String? endLocator,
    String? excerpt,
    int? chapterIndex,
    String? chapterTitle,
    String? note,
    bool? orphaned,
    DateTime? updatedAt,
  }) {
    return Annotation(
      id: id,
      documentId: documentId,
      kind: kind ?? this.kind,
      startLocator: startLocator ?? this.startLocator,
      endLocator: endLocator ?? this.endLocator,
      excerpt: excerpt ?? this.excerpt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      note: note ?? this.note,
      orphaned: orphaned ?? this.orphaned,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Annotation &&
      other.id == id &&
      other.kind == kind &&
      other.startLocator == startLocator &&
      other.endLocator == endLocator &&
      other.excerpt == excerpt &&
      other.note == note &&
      other.orphaned == orphaned &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    startLocator,
    endLocator,
    excerpt,
    note,
    orphaned,
    updatedAt,
  );
}
