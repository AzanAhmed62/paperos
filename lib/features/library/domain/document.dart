import 'package:flutter/foundation.dart';

/// Document formats PaperOS knows about.
///
/// The enum is wider than what the current reader can open. That is
/// intentional: a format is *recognised* long before it is *readable*, which
/// lets the library show honest metadata and lets a new engine be added later
/// without touching the storage layer or any other screen.
enum DocumentFormat {
  pdf('pdf', 'PDF', <String>['pdf']),
  text('txt', 'TXT', <String>['txt', 'text', 'log', 'nfo'], paged: false),
  markdown('md', 'Markdown', <String>['md', 'markdown', 'mdown']),
  epub('epub', 'EPUB', <String>['epub']),
  html('html', 'HTML', <String>['html', 'htm', 'xhtml']),
  word('docx', 'DOCX', <String>['docx', 'doc', 'odt']),
  comic('cbz', 'Comic', <String>['cbz', 'cbr', 'cb7', 'cbt']),
  unknown('bin', 'File', <String>[]);

  const DocumentFormat(
    this.id,
    this.label,
    this.extensions, {
    this.paged = true,
  });

  final String id;
  final String label;
  final List<String> extensions;

  /// Whether reading is naturally page based. Continuous formats (plain text)
  /// are still paginated by the reader, but their stored position is a
  /// fraction of the document rather than a page number.
  final bool paged;

  /// Every extension PaperOS is willing to look at in a file picker.
  static List<String> get importableExtensions => <String>[
    for (final DocumentFormat format in DocumentFormat.values)
      ...format.extensions,
  ];

  /// Extensions the current build can actually open.
  static List<String> get readableExtensions => <String>[
    ...DocumentFormat.pdf.extensions,
    ...DocumentFormat.text.extensions,
  ];

  /// Whether the current build has a reader for [format].
  ///
  /// Deliberately a property of the enum rather than a hard-coded pair of
  /// comparisons: adding a reader means adding one `true` here, and no screen
  /// has to be edited.
  static bool isReadable(DocumentFormat format) =>
      format == DocumentFormat.pdf || format == DocumentFormat.text;

  static DocumentFormat? tryParse(String id) {
    for (final DocumentFormat format in DocumentFormat.values) {
      if (format.id == id) return format;
    }
    return null;
  }

  static DocumentFormat fromFileName(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return DocumentFormat.unknown;
    return fromExtension(fileName.substring(dot + 1));
  }

  static DocumentFormat fromExtension(String extension) {
    final String needle = extension.toLowerCase();
    for (final DocumentFormat format in DocumentFormat.values) {
      if (format.extensions.contains(needle)) return format;
    }
    return DocumentFormat.unknown;
  }
}

/// Whether a library entry can be opened.
enum DocumentStatus {
  /// Import succeeded and the format is supported.
  ready('ready'),

  /// The file was imported but could not be parsed. Kept in the library so the
  /// user can see and delete it instead of wondering where it went.
  unreadable('unreadable'),

  /// The underlying file has disappeared since import.
  missing('missing');

  const DocumentStatus(this.id);

  final String id;

  static DocumentStatus parse(String id) {
    for (final DocumentStatus status in DocumentStatus.values) {
      if (status.id == id) return status;
    }
    return DocumentStatus.ready;
  }
}

/// A place inside a document.
///
/// [page] is authoritative when present: PDF pages and the paginated pages of a
/// text document both store an exact page number. [fraction] is stored
/// alongside it for continuous documents so that a library row can show a
/// sensible progress bar without reopening the file, and is the only locator
/// when [page] is null.
@immutable
class ReadingPosition {
  const ReadingPosition({this.page, this.fraction});

  const ReadingPosition.atPage(int this.page) : fraction = null;

  const ReadingPosition.atFraction(this.fraction) : page = null;

  static const ReadingPosition start = ReadingPosition.atPage(1);

  /// 1-based page number, or null when only a fraction is known.
  final int? page;

  /// 0..1 through the document, or null when only a page is known.
  final double? fraction;

  bool get isPaged => page != null;

  /// Normalised 0..1 position, excluding the page being read.
  double unitFor(int pageCount) {
    if (pageCount <= 0) return 0;
    if (page != null) return ((page! - 1).clamp(0, pageCount - 1) / pageCount);
    return fraction!.clamp(0.0, 1.0);
  }

  /// 0..1 progress including the page currently being read.
  double progressFor(int pageCount) {
    if (pageCount <= 0) return 0;
    if (page != null) return (page!.clamp(1, pageCount) / pageCount);
    return fraction!.clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is ReadingPosition &&
      other.page == page &&
      other.fraction == fraction;

  @override
  int get hashCode => Object.hash(page, fraction);

  @override
  String toString() => page != null
      ? 'ReadingPosition(page: $page)'
      : 'ReadingPosition(fraction: $fraction)';
}

/// Persistent reading state for one document.
@immutable
class ReadingProgress {
  const ReadingProgress({this.position, this.maxPage, required this.pageCount});

  static const ReadingProgress none = ReadingProgress(
    position: null,
    maxPage: null,
    pageCount: 0,
  );

  final ReadingPosition? position;
  final int? maxPage;
  final int pageCount;

  bool get hasStarted => position != null;

  bool get isFinished {
    final ReadingPosition? current = position;
    if (current == null || pageCount <= 0) return false;
    return current.progressFor(pageCount) >= 0.995;
  }

  /// 0..1. Zero when nothing is known, never null, never a guess.
  double get fraction {
    final ReadingPosition? current = position;
    if (current == null || pageCount <= 0) return 0;
    return current.progressFor(pageCount);
  }

  ReadingProgress copyWith({
    ReadingPosition? position,
    int? maxPage,
    int? pageCount,
  }) {
    return ReadingProgress(
      position: position ?? this.position,
      maxPage: maxPage ?? this.maxPage,
      pageCount: pageCount ?? this.pageCount,
    );
  }
}

/// A user-placed mark inside a document.
@immutable
class Bookmark {
  const Bookmark({
    required this.id,
    required this.documentId,
    required this.page,
    required this.fraction,
    this.label,
    this.excerpt,
    required this.createdAt,
  });

  final String id;
  final String documentId;
  final int page;
  final double fraction;
  final String? label;
  final String? excerpt;
  final DateTime createdAt;

  ReadingPosition get position => page >= 0
      ? ReadingPosition(page: page, fraction: fraction >= 0 ? fraction : null)
      : ReadingPosition.atFraction(fraction < 0 ? 0 : fraction);

  /// Whether [other] points at the same place as this bookmark.
  ///
  /// Pages win over fractions: a paginated text document records a measured
  /// page number, and comparing the fraction as well would produce false
  /// negatives whenever the page-count estimate shifted between sessions.
  bool pointsAt(ReadingPosition other) {
    if (page >= 0 && other.page != null) return page == other.page;
    final double a = fraction < 0 ? 0 : fraction;
    final double b = other.fraction ?? 0;
    return (a - b).abs() < 0.005;
  }

  /// The best available human label: an explicit label if the user set one,
  /// otherwise the position within the document.
  String get displayLabel =>
      label?.trim().isNotEmpty == true ? label! : describe(0);

  /// "Page 42" or "38%" depending on the format.
  String describe(int pageCount) {
    if (page >= 0) {
      return pageCount > 0 ? 'Page $page of $pageCount' : 'Page $page';
    }
    final int percent = (fraction.clamp(0.0, 1.0) * 100).round();
    return '$percent%';
  }

  @override
  bool operator ==(Object other) =>
      other is Bookmark &&
      other.id == id &&
      other.documentId == documentId &&
      other.page == page &&
      other.fraction == fraction &&
      other.label == label &&
      other.excerpt == excerpt;

  @override
  int get hashCode =>
      Object.hash(id, documentId, page, fraction, label, excerpt);
}

/// A file in the PaperOS library.
@immutable
class Document {
  const Document({
    required this.id,
    required this.localPath,
    required this.sourceUri,
    required this.sourceName,
    required this.title,
    required this.format,
    required this.byteSize,
    required this.pageCount,
    required this.status,
    required this.isFavorite,
    required this.progress,
    required this.addedAt,
    required this.lastOpenedAt,
    required this.openedSeconds,
  });

  final String id;

  /// Absolute path of PaperOS' private copy of the file.
  final String localPath;

  /// The `content://` (or `file://`) location the file was imported from.
  final String? sourceUri;

  /// Original file name including extension.
  final String sourceName;

  /// Display title. Defaults to the file name without extension, and can be
  /// replaced by metadata read from the document itself.
  final String title;

  final DocumentFormat format;
  final int byteSize;
  final int? pageCount;
  final DocumentStatus status;
  final bool isFavorite;
  final ReadingProgress progress;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;

  /// Cumulative time the reader has been open for this document.
  final int openedSeconds;

  bool get isReadable => status == DocumentStatus.ready;

  bool get wasOpened => lastOpenedAt != null;

  /// 0..1 reading progress, for progress bars and "continue reading".
  double get progressFraction => progress.fraction;

  Document copyWith({
    String? title,
    int? pageCount,
    DocumentStatus? status,
    bool? isFavorite,
    ReadingProgress? progress,
    DateTime? lastOpenedAt,
    int? openedSeconds,
  }) {
    return Document(
      id: id,
      localPath: localPath,
      sourceUri: sourceUri,
      sourceName: sourceName,
      title: title ?? this.title,
      format: format,
      byteSize: byteSize,
      pageCount: pageCount ?? this.pageCount,
      status: status ?? this.status,
      isFavorite: isFavorite ?? this.isFavorite,
      progress: progress ?? this.progress,
      addedAt: addedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      openedSeconds: openedSeconds ?? this.openedSeconds,
    );
  }

  @override
  bool operator ==(Object other) => other is Document && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
