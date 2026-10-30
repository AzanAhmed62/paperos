import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Publication metadata read from an EPUB package document.
///
/// Fields are nullable because a malformed or minimal EPUB is allowed to omit
/// them. The library falls back to the file name; PaperOS never invents an
/// author or publisher.
@immutable
class EpubMetadata {
  const EpubMetadata({
    this.title,
    this.author,
    this.publisher,
    this.language,
    this.identifier,
    this.description,
  });

  final String? title;
  final String? author;
  final String? publisher;
  final String? language;
  final String? identifier;
  final String? description;
}

/// One spine item after its XHTML has been reduced to readable text.
///
/// [start] and [end] are offsets into [EpubBook.text]; [bodyStart] is the
/// offset of the first character of [text] (the composite may prepend a
/// chapter heading). [anchorOffsets] maps XHTML `id` attributes to offsets
/// relative to [text], so a nested table of contents can point inside a
/// chapter without pretending every TOC row is a whole spine item.
@immutable
class EpubChapter {
  const EpubChapter({
    required this.index,
    required this.href,
    required this.title,
    required this.text,
    required this.start,
    required this.bodyStart,
    required this.end,
    required this.anchorOffsets,
  });

  final int index;
  final String href;
  final String title;
  final String text;
  final int start;
  final int bodyStart;
  final int end;
  final Map<String, int> anchorOffsets;

  int get length => text.length;

  int get contentLength => end - start;

  EpubChapter withCompositeRange({
    required int start,
    required int bodyStart,
    required int end,
  }) {
    return EpubChapter(
      index: index,
      href: href,
      title: title,
      text: text,
      start: start,
      bodyStart: bodyStart,
      end: end,
      anchorOffsets: anchorOffsets,
    );
  }
}

/// A row in the nested table of contents.
@immutable
class EpubTocEntry {
  const EpubTocEntry({
    required this.title,
    required this.chapterIndex,
    required this.charOffset,
    required this.depth,
    this.children = const <EpubTocEntry>[],
  });

  final String title;

  /// 0-based spine index, or null when the navigation target is not part of
  /// the reading order and therefore cannot be opened.
  final int? chapterIndex;

  /// Character offset relative to the chapter text.
  final int charOffset;
  final int depth;
  final List<EpubTocEntry> children;

  Iterable<EpubTocEntry> get flattened sync* {
    yield this;
    for (final EpubTocEntry child in children) {
      yield* child.flattened;
    }
  }
}

/// A stable location in an EPUB, independent of pagination.
///
/// This is intentionally described as CFI-like rather than EPUB CFI: PaperOS
/// renders extracted text rather than a DOM, so a literal EPUB CFI (which
/// addresses DOM nodes) would be false precision. The chapter index and
/// chapter-relative character offset are stable across fonts, margins and
/// screen sizes.
@immutable
class EpubLocator {
  const EpubLocator({required this.spineIndex, required this.charOffset});

  final int spineIndex;
  final int charOffset;

  static final RegExp _pattern = RegExp(r'^epub:spine=(\d+);char=(\d+)$');

  static EpubLocator? tryParse(String? value) {
    if (value == null) return null;
    final RegExpMatch? match = _pattern.firstMatch(value.trim());
    if (match == null) return null;
    final int? spine = int.tryParse(match.group(1)!);
    final int? offset = int.tryParse(match.group(2)!);
    if (spine == null || offset == null || spine < 0 || offset < 0) {
      return null;
    }
    return EpubLocator(spineIndex: spine, charOffset: offset);
  }

  @override
  String toString() => 'epub:spine=$spineIndex;char=$charOffset';

  @override
  bool operator ==(Object other) =>
      other is EpubLocator &&
      other.spineIndex == spineIndex &&
      other.charOffset == charOffset;

  @override
  int get hashCode => Object.hash(spineIndex, charOffset);
}

/// A resolved chapter-local text range.
@immutable
class EpubTextLocation {
  const EpubTextLocation({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.charOffset,
    required this.globalOffset,
  });

  final int chapterIndex;
  final String chapterTitle;
  final int charOffset;
  final int globalOffset;
}

/// One search hit. [excerpt] is a collapsed, windowed view of the passage.
@immutable
class EpubSearchResult {
  const EpubSearchResult({
    required this.query,
    required this.excerpt,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.globalOffset,
    required this.charOffset,
  });

  final String query;
  final String excerpt;
  final int chapterIndex;
  final String chapterTitle;
  final int globalOffset;
  final int charOffset;

  EpubLocator get locator =>
      EpubLocator(spineIndex: chapterIndex, charOffset: charOffset);
}

/// A set of annotations resolved to the current page's character range.
@immutable
class EpubAnnotationSpan {
  const EpubAnnotationSpan({
    required this.annotationId,
    required this.kind,
    required this.start,
    required this.end,
    required this.hasNote,
  });

  final String annotationId;

  /// AnnotationKind.id, kept as a string so this low-level rendering type does
  /// not import the annotation feature.
  final String kind;
  final int start;
  final int end;
  final bool hasNote;
}

/// A fully parsed EPUB: metadata, reading order, extracted text and TOC.
class EpubBook {
  EpubBook({
    required this.metadata,
    required List<EpubChapter> chapters,
    required List<EpubTocEntry> toc,
  }) : chapters = List<EpubChapter>.unmodifiable(chapters),
       toc = List<EpubTocEntry>.unmodifiable(toc) {
    _buildCompositeText();
  }

  final EpubMetadata metadata;
  final List<EpubChapter> chapters;
  final List<EpubTocEntry> toc;

  String _text = '';
  final List<EpubChapter> _composite = <EpubChapter>[];

  String get text => _text;

  /// Chapters with their composite offsets attached.
  List<EpubChapter> get compositeChapters =>
      List<EpubChapter>.unmodifiable(_composite);

  void _buildCompositeText() {
    final StringBuffer buffer = StringBuffer();
    for (final EpubChapter chapter in chapters) {
      if (buffer.length > 0) buffer.write('\n\n');
      final int start = buffer.length;
      final String trimmed = chapter.text.trimLeft();
      final String title = chapter.title.trim();
      final String heading = title.isEmpty || _startsWithTitle(trimmed, title)
          ? ''
          : '$title\n\n';
      buffer.write(heading);
      final int bodyStart = buffer.length;
      buffer.write(chapter.text);
      final int end = buffer.length;
      _composite.add(
        chapter.withCompositeRange(
          start: start,
          bodyStart: bodyStart,
          end: end,
        ),
      );
    }
    _text = buffer.toString();
  }

  static bool _startsWithTitle(String text, String title) {
    if (text.length < title.length) return false;
    return text.substring(0, title.length).toLowerCase() == title.toLowerCase();
  }

  EpubChapter? chapterAt(int index) {
    if (index < 0 || index >= _composite.length) return null;
    return _composite[index];
  }

  /// The chapter containing [globalOffset]. Offsets in the separator between
  /// two chapters resolve to the following chapter, which is where the reader
  /// visually continues.
  EpubTextLocation? locate(int globalOffset) {
    if (_composite.isEmpty) return null;
    final int offset = globalOffset.clamp(0, _text.length);
    final int found = _chapterIndexFor(offset);
    final EpubChapter chapter = _composite[found];
    final int local = (offset - chapter.bodyStart).clamp(
      0,
      chapter.text.length,
    );
    return EpubTextLocation(
      chapterIndex: chapter.index,
      chapterTitle: chapter.title,
      charOffset: local,
      globalOffset: chapter.bodyStart + local,
    );
  }

  int _chapterIndexFor(int offset) {
    int low = 0;
    int high = _composite.length - 1;
    int candidate = 0;
    while (low <= high) {
      final int mid = low + ((high - low) >> 1);
      if (_composite[mid].start <= offset) {
        candidate = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    while (candidate + 1 < _composite.length &&
        offset >= _composite[candidate].end) {
      candidate++;
    }
    return candidate;
  }

  /// Global offset for a chapter-local character offset, clamped to the body.
  int globalOffset(int chapterIndex, int charOffset) {
    final EpubChapter? chapter = chapterAt(chapterIndex);
    if (chapter == null) {
      return _text.isEmpty ? 0 : _text.length;
    }
    final int local = charOffset.clamp(0, chapter.text.length);
    return chapter.bodyStart + local;
  }

  EpubLocator locatorAt(int globalOffset) {
    final EpubTextLocation? location = locate(globalOffset);
    if (location == null) {
      return const EpubLocator(spineIndex: 0, charOffset: 0);
    }
    return EpubLocator(
      spineIndex: location.chapterIndex,
      charOffset: location.charOffset,
    );
  }

  EpubTextLocation? locateLocator(EpubLocator locator) {
    final EpubChapter? chapter = chapterAt(locator.spineIndex);
    if (chapter == null) return null;
    return EpubTextLocation(
      chapterIndex: chapter.index,
      chapterTitle: chapter.title,
      charOffset: locator.charOffset.clamp(0, chapter.text.length),
      globalOffset: globalOffset(locator.spineIndex, locator.charOffset),
    );
  }

  bool canResolve(String locator) {
    final EpubLocator? parsed = EpubLocator.tryParse(locator);
    return parsed != null && chapterAt(parsed.spineIndex) != null;
  }

  String chapterTitleAt(int globalOffset) {
    return locate(globalOffset)?.chapterTitle ?? '';
  }

  int pageFractionOffset(double fraction) {
    if (_text.isEmpty) return 0;
    return (fraction.clamp(0.0, 1.0) * _text.length).floor();
  }

  /// Finds a passage in a chapter even when a stored character offset drifted
  /// because a book was re-imported with slightly different markup.
  ///
  /// Returns null when the chapter is gone or the excerpt no longer exists.
  int? recoverAnchor(EpubLocator locator, String excerpt) {
    final EpubChapter? chapter = chapterAt(locator.spineIndex);
    if (chapter == null) return null;
    final String needle = excerpt.trim();
    if (needle.isEmpty) return null;
    final String haystack = chapter.text;
    final int exact = haystack.indexOf(needle);
    if (exact >= 0) return globalOffset(locator.spineIndex, exact);
    final String lowerHaystack = haystack.toLowerCase();
    final String lowerNeedle = needle.toLowerCase();
    final int loose = lowerHaystack.indexOf(lowerNeedle);
    if (loose >= 0) return globalOffset(locator.spineIndex, loose);
    return null;
  }

  /// In-book search, case-insensitive, with a short readable excerpt.
  List<EpubSearchResult> search(String query, {int limit = 120}) {
    final String needle = query.trim();
    if (needle.isEmpty || _text.isEmpty) return const <EpubSearchResult>[];
    final String lowerText = _text.toLowerCase();
    final String lowerNeedle = needle.toLowerCase();
    final List<EpubSearchResult> results = <EpubSearchResult>[];
    int from = 0;
    while (results.length < limit) {
      final int index = lowerText.indexOf(lowerNeedle, from);
      if (index < 0) break;
      final EpubTextLocation? location = locate(index);
      if (location != null) {
        results.add(
          EpubSearchResult(
            query: needle,
            excerpt: _excerptAround(_text, index, index + needle.length),
            chapterIndex: location.chapterIndex,
            chapterTitle: location.chapterTitle,
            globalOffset: index,
            charOffset: location.charOffset,
          ),
        );
      }
      from = math.max(index + needle.length, index + 1);
    }
    return results;
  }

  static String _excerptAround(String text, int start, int end) {
    const int context = 70;
    final int from = math.max(0, start - context);
    final int to = math.min(text.length, end + context);
    String excerpt = text.substring(from, to).replaceAll(RegExp(r'\s+'), ' ');
    excerpt = excerpt.trim();
    if (from > 0) excerpt = '…$excerpt';
    if (to < text.length) excerpt = '$excerpt…';
    return excerpt;
  }

  /// Resolves an annotation anchor to a global range, with a best-effort
  /// excerpt recovery when the character offset no longer matches.
  int? resolveAnchor(String locator, {String? excerpt}) {
    final EpubLocator? parsed = EpubLocator.tryParse(locator);
    if (parsed == null) return null;
    final EpubTextLocation? location = locateLocator(parsed);
    if (location == null) return null;
    if (excerpt != null && excerpt.trim().isNotEmpty) {
      final int recovered = recoverAnchor(parsed, excerpt) ?? -1;
      if (recovered >= 0) return recovered;
    }
    return location.globalOffset;
  }
}
