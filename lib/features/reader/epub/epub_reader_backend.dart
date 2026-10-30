import '../../annotations/domain/annotation.dart';
import '../../library/domain/document.dart';
import '../domain/reader_backend.dart';
import '../domain/text_paginator.dart';
import 'epub_book.dart';

/// A chapter-local selection ready to be stored as an annotation.
class EpubSelection {
  const EpubSelection({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.startLocator,
    required this.endLocator,
    required this.excerpt,
  });

  final int chapterIndex;
  final String chapterTitle;
  final String startLocator;
  final String endLocator;
  final String excerpt;
}

/// Reads an extracted EPUB through the same page-oriented contract as PDF and
/// TXT, while adding the operations unique to a reflowable book: locators,
/// nested TOC, in-book search and annotation anchors.
class EpubReaderBackend implements ReaderBackend {
  EpubReaderBackend({required this.book, required this.paginator}) {
    if (book.chapters.isNotEmpty) {
      _index = _pageForLocator(EpubLocator(spineIndex: 0, charOffset: 0));
      paginator.pageAt(_index);
    }
  }

  final EpubBook book;
  final TextPaginator paginator;

  int _index = 0;

  @override
  ReaderFormat get format => ReaderFormat.epub;

  @override
  int get pageCount => paginator.pageCount;

  @override
  int get pageIndex => _index;

  @override
  bool get isPageCountExact => paginator.isComplete;

  @override
  double get progress {
    if (pageCount <= 0) return 0;
    return ((_index + 1) / pageCount).clamp(0.0, 1.0);
  }

  @override
  String get positionLabel {
    final String chapter = chapterTitleForPage(_index);
    final String page = 'Page ${_index + 1} of $pageCount';
    return chapter.isEmpty ? page : '$chapter · $page';
  }

  @override
  double? get pageAspectRatio => null;

  @override
  Future<void> goToPage(int index) async {
    _index = index.clamp(0, pageCount - 1);
    paginator.pageAt(_index);
  }

  @override
  Future<bool> next() async {
    if (_index >= pageCount - 1) return false;
    _index++;
    paginator.pageAt(_index);
    return true;
  }

  @override
  Future<bool> previous() async {
    if (_index <= 0) return false;
    _index--;
    paginator.pageAt(_index);
    return true;
  }

  @override
  Future<void> dispose() async {
    paginator.dispose();
  }

  // ------------------------------------------------------------- locations

  TextPage get currentPage => paginator.pageAt(_index);

  @override
  String? get currentLocator => locatorAtPage(_index).toString();

  @override
  double get textFraction => fractionForLocator(currentLocator);

  EpubLocator locatorAtPage(int pageIndex) {
    final TextPage page = paginator.pageAt(pageIndex);
    return book.locatorAt(page.start);
  }

  int pageForLocator(String? locator) {
    final EpubLocator? parsed = EpubLocator.tryParse(locator);
    if (parsed == null) return -1;
    return _pageForLocator(parsed);
  }

  int _pageForLocator(EpubLocator locator) {
    final EpubTextLocation? location = book.locateLocator(locator);
    if (location == null) return -1;
    return pageForOffset(location.globalOffset);
  }

  int pageForOffset(int offset) {
    if (book.text.isEmpty) return 0;
    final int target = offset.clamp(0, book.text.length);
    int index = 0;
    // Pagination is lazy; materialising the page containing the target is the
    // only reliable way to restore a locator after a typography change.
    int guard = 0;
    while (guard < 200000) {
      final TextPage page = paginator.pageAt(index);
      if (target < page.end) return index;
      if (page.end >= book.text.length) return index;
      index++;
      guard++;
    }
    return (pageCount - 1).clamp(0, pageCount - 1);
  }

  bool goToLocator(String? locator) {
    final int page = pageForLocator(locator);
    if (page < 0) return false;
    _index = page.clamp(0, pageCount - 1);
    paginator.pageAt(_index);
    return true;
  }

  bool goToOffset(int offset) {
    if (book.text.isEmpty) return false;
    _index = pageForOffset(offset);
    paginator.pageAt(_index);
    return true;
  }

  bool goToTocEntry(EpubTocEntry entry) {
    final int? chapter = entry.chapterIndex;
    if (chapter == null) return false;
    return goToOffset(book.globalOffset(chapter, entry.charOffset));
  }

  String chapterTitleForPage(int pageIndex) {
    final TextPage page = paginator.pageAt(pageIndex);
    return book.chapterTitleAt(page.start);
  }

  String chapterTitleForLocator(String? locator) {
    final EpubLocator? parsed = EpubLocator.tryParse(locator);
    if (parsed == null) return '';
    return book.locateLocator(parsed)?.chapterTitle ?? '';
  }

  double fractionForLocator(String? locator) {
    final EpubLocator? parsed = EpubLocator.tryParse(locator);
    if (parsed == null) return 0;
    final EpubTextLocation? location = book.locateLocator(parsed);
    if (location == null) return 0;
    if (book.text.isEmpty) return 0;
    return (location.globalOffset / book.text.length).clamp(0.0, 1.0);
  }

  int offsetForFraction(double fraction) {
    if (book.text.isEmpty) return 0;
    return (book.text.length * fraction.clamp(0.0, 1.0)).floor();
  }

  // -------------------------------------------------------------- searching

  List<EpubSearchResult> search(String query, {int limit = 120}) =>
      book.search(query, limit: limit);

  // ------------------------------------------------------------ annotations

  EpubSelection? selectionFor(int start, int end) {
    if (book.text.isEmpty) return null;
    final int first = start.clamp(0, book.text.length - 1);
    final int last = end.clamp(first + 1, book.text.length);
    final EpubTextLocation? startLocation = book.locate(first);
    if (startLocation == null) return null;
    final EpubChapter? chapter = book.chapterAt(startLocation.chapterIndex);
    if (chapter == null) return null;

    final int bodyStart = chapter.bodyStart;
    final int chapterEnd = chapter.bodyStart + chapter.text.length;
    final int clippedStart = first.clamp(bodyStart, chapterEnd);
    final int clippedEnd = last.clamp(clippedStart, chapterEnd);
    if (clippedEnd <= clippedStart) return null;
    final String excerpt = book.text
        .substring(clippedStart, clippedEnd)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (excerpt.isEmpty) return null;

    // Keep both ends in the same chapter. `locate()` intentionally maps an
    // offset at the chapter boundary to the next chapter, which would make the
    // exclusive end locator jump across the heading and separator gap.
    final EpubLocator startLocator = EpubLocator(
      spineIndex: chapter.index,
      charOffset: clippedStart - chapter.bodyStart,
    );
    final EpubLocator endLocator = EpubLocator(
      spineIndex: chapter.index,
      charOffset: clippedEnd - chapter.bodyStart,
    );
    return EpubSelection(
      chapterIndex: chapter.index,
      chapterTitle: chapter.title,
      startLocator: startLocator.toString(),
      endLocator: endLocator.toString(),
      excerpt: excerpt.length <= 500
          ? excerpt
          : '${excerpt.substring(0, 499)}…',
    );
  }

  /// Global text range for an annotation, or null when its anchor is no longer
  /// resolvable. Recovery by excerpt is deliberately attempted only inside the
  /// remembered chapter so a repeated phrase in another chapter cannot move a
  /// highlight.
  ({int start, int end})? annotationRange(Annotation annotation) {
    if (annotation.orphaned) return null;
    final EpubLocator? startLocator = EpubLocator.tryParse(
      annotation.startLocator,
    );
    final EpubLocator? endLocator = EpubLocator.tryParse(annotation.endLocator);
    if (startLocator == null || endLocator == null) return null;
    final EpubChapter? startChapter = book.chapterAt(startLocator.spineIndex);
    if (startChapter == null) return null;

    final int? recoveredStart = book.resolveAnchor(
      annotation.startLocator,
      excerpt: annotation.excerpt,
    );
    final int start =
        recoveredStart ??
        book.globalOffset(startLocator.spineIndex, startLocator.charOffset);
    int end;
    if (endLocator.spineIndex == startLocator.spineIndex) {
      end = book.globalOffset(endLocator.spineIndex, endLocator.charOffset);
      if (recoveredStart != null &&
          (end - start - annotation.excerpt.length).abs() > 2) {
        end = start + annotation.excerpt.length;
      }
    } else {
      end = book.globalOffset(endLocator.spineIndex, endLocator.charOffset);
    }
    end = end.clamp(start, book.text.length);
    if (end <= start) {
      end = (start + annotation.excerpt.length).clamp(start, book.text.length);
    }
    if (end <= start) return null;
    return (start: start, end: end);
  }

  bool canResolveAnnotation(Annotation annotation) =>
      annotationRange(annotation) != null;

  List<EpubAnnotationSpan> spansForPage(
    int pageIndex,
    Iterable<Annotation> annotations,
  ) {
    final TextPage page = paginator.pageAt(pageIndex);
    final List<EpubAnnotationSpan> spans = <EpubAnnotationSpan>[];
    for (final Annotation annotation in annotations) {
      final ({int start, int end})? range = annotationRange(annotation);
      if (range == null) continue;
      final int start = range.start.clamp(page.start, page.end);
      final int end = range.end.clamp(page.start, page.end);
      if (end <= start) continue;
      spans.add(
        EpubAnnotationSpan(
          annotationId: annotation.id,
          kind: annotation.kind.id,
          start: start,
          end: end,
          hasNote: annotation.hasNote,
        ),
      );
    }
    spans.sort((EpubAnnotationSpan a, EpubAnnotationSpan b) {
      final int byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.end.compareTo(b.end);
    });
    return spans;
  }

  /// Full text with all resolvable annotation spans as global offsets. Used by
  /// scroll mode and by the annotation library for jumping.
  List<EpubAnnotationSpan> annotationSpans(Iterable<Annotation> annotations) {
    final List<EpubAnnotationSpan> spans = <EpubAnnotationSpan>[];
    for (final Annotation annotation in annotations) {
      final ({int start, int end})? range = annotationRange(annotation);
      if (range == null) continue;
      spans.add(
        EpubAnnotationSpan(
          annotationId: annotation.id,
          kind: annotation.kind.id,
          start: range.start,
          end: range.end,
          hasNote: annotation.hasNote,
        ),
      );
    }
    spans.sort((EpubAnnotationSpan a, EpubAnnotationSpan b) {
      final int byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.end.compareTo(b.end);
    });
    return spans;
  }

  ReadingPosition positionAtPage(int pageIndex) {
    final EpubLocator locator = locatorAtPage(pageIndex);
    final double pageProgress = pageCount <= 0
        ? 0
        : ((pageIndex + 1) / pageCount).clamp(0.0, 1.0);
    return ReadingPosition(
      page: pageIndex + 1,
      fraction: pageProgress,
      locator: locator.toString(),
    );
  }
}
