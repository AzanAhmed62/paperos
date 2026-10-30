import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../config/app_config.dart';
import '../../../core/errors/paper_exception.dart';
import '../../../core/platform/pdf_service.dart';
import '../../../core/utils/async_utils.dart';
import '../../../theme/paper_typography.dart';
import '../../annotations/domain/annotation.dart';
import '../../library/data/bookmark_repository.dart';
import '../../library/data/document_repository.dart';
import '../../library/domain/document.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/app_settings.dart';
import '../domain/reader_backend.dart';
import '../domain/text_paginator.dart';
import '../epub/epub_book.dart';
import '../epub/epub_parser.dart';
import '../epub/epub_reader_backend.dart';

/// One reading session.
///
/// Owns the backend, the current page, the bookmark list, annotations and the
/// write-behind progress store. Everything format specific lives behind
/// [ReaderBackend], while EPUB-only operations are routed to
/// [EpubReaderBackend] when that is the active backend.
class ReaderSession extends AsyncNotifier<ReaderState> {
  /// Injected by the family constructor.
  ReaderSession(this.documentId);

  final String documentId;

  ReaderBackend? _backend;
  DocumentRepository? _documents;
  ReaderState? _latestState;
  final Debouncer _saveDebouncer = Debouncer(
    delay: PaperConfig.progressWriteDebounce,
  );

  DateTime? _segmentStart;
  Duration _accumulated = Duration.zero;
  Timer? _idleSaveTimer;
  Size _viewport = Size.zero;
  int _scrollRequestId = 0;

  EpubReaderBackend? get epubBackend {
    final ReaderBackend? backend = _backend;
    return backend is EpubReaderBackend ? backend : null;
  }

  @override
  Future<ReaderState> build() async {
    ref.onDispose(() {
      _idleSaveTimer?.cancel();
      _saveDebouncer.cancel();
      // Do not touch `ref` or the provider state here: Riverpod forbids both
      // during disposal. The repository and the latest snapshot were captured
      // while the session was alive.
      final ReaderState? current = _latestState;
      final DocumentRepository? documents = _documents;
      if (current != null && documents != null) {
        unawaited(_writeProgress(current, documents, closeSegment: true));
      }
      final ReaderBackend? backend = _backend;
      _backend = null;
      if (backend != null) unawaited(backend.dispose());
    });

    final DocumentRepository documents = ref.watch(documentRepositoryProvider);
    _documents = documents;

    final Document? stored = await documents.findById(documentId);
    if (stored == null) {
      throw const PaperException.missingFile(
        'This document is no longer in your library.',
      );
    }
    final Document document = await ref
        .read(libraryServiceProvider)
        .verifyReadable(stored);

    final ReaderSettings settings = ref.read(settingsProvider).reader;
    final ReaderBackend backend = await _createBackend(document, settings);
    // Track the backend before any further await: if loading bookmarks or
    // annotations fails, the provider still has an error state, and its
    // disposal hook must be able to release the native PDF handle/paginator.
    _backend = backend;

    final ReadingPosition? saved = document.progress.position;
    if (saved != null) {
      await _restore(backend, saved);
    }

    _segmentStart = DateTime.now();
    _accumulated = Duration.zero;

    final List<Bookmark> bookmarks = await ref
        .read(bookmarkRepositoryProvider)
        .listFor(documentId);
    final List<Annotation> annotations = await _loadAnnotations(backend);

    final ReaderState initial = ReaderState(
      document: document,
      backend: backend,
      bookmarks: bookmarks,
      annotations: annotations,
    );
    _latestState = initial;
    return initial;
  }

  /// Updates the visible state and the disposal snapshot together.
  ///
  /// The snapshot lets the provider's `onDispose` write progress without
  /// reading `state`, which Riverpod forbids during disposal.
  void _setState(ReaderState next) {
    _latestState = next;
    state = AsyncData(next);
  }

  Future<void> _restore(ReaderBackend backend, ReadingPosition saved) async {
    if (backend is EpubReaderBackend) {
      if (saved.locator != null && backend.goToLocator(saved.locator)) return;
      if (saved.fraction != null) {
        backend.goToOffset(backend.offsetForFraction(saved.fraction!));
        return;
      }
    }
    if (saved.page != null) {
      await backend.goToPage((saved.page! - 1).clamp(0, backend.pageCount - 1));
      return;
    }
    if (saved.fraction != null) {
      await backend.goToPage(_pageForFraction(backend, saved.fraction!));
    }
  }

  Future<List<Annotation>> _loadAnnotations(ReaderBackend backend) async {
    final repository = ref.read(annotationRepositoryProvider);
    List<Annotation> annotations = await repository.listFor(documentId);
    if (backend is! EpubReaderBackend) return annotations;

    // Keep an annotation whose anchor drifted: mark it unresolved once, show
    // the excerpt and note in the library, and let the user delete it. Never
    // silently discard a note.
    bool changed = false;
    for (final Annotation annotation in annotations) {
      if (annotation.orphaned) continue;
      if (!backend.canResolveAnnotation(annotation)) {
        await repository.markOrphaned(annotation.id);
        changed = true;
      }
    }
    if (changed) {
      annotations = await repository.listFor(documentId);
    }
    return annotations;
  }

  // ------------------------------------------------------------------ backend

  Future<ReaderBackend> _createBackend(
    Document document,
    ReaderSettings settings,
  ) async {
    final File file = File(document.localPath);
    if (!file.existsSync()) {
      throw const PaperException.missingFile(
        'The file for this document is no longer on the device.',
      );
    }

    if (document.format == DocumentFormat.pdf) {
      final PdfDocumentHandle handle = await ref
          .read(pdfServiceProvider)
          .open(document.localPath);
      return PdfReaderBackend(handle, ref.read(pdfServiceProvider));
    }

    if (document.format == DocumentFormat.text) {
      final int length = file.lengthSync();
      if (length > PaperConfig.maxTextReaderBytes) {
        throw PaperException.unsupportedFormat(
          'This text file is too large to paginate on this device '
          '(${(length / (1024 * 1024)).round()} MB).',
        );
      }
      return _textBackend(document, await file.readAsString(), settings);
    }

    if (document.format == DocumentFormat.epub) {
      final EpubParseResult parsed;
      try {
        parsed = ref.read(epubParserProvider).parseFile(document.localPath);
      } on EpubParseException catch (error) {
        throw PaperException.corruptDocument(error.message);
      }
      return _epubBackend(parsed.book, settings);
    }

    throw PaperException.unsupportedFormat(
      'PaperOS does not open ${document.format.label} files yet.',
    );
  }

  TextReaderBackend _textBackend(
    Document document,
    String text,
    ReaderSettings settings,
  ) {
    return TextReaderBackend(
      title: document.title,
      paginator: TextPaginator(
        text: text,
        style: _readingTextStyle(settings),
        width: _textWidth(settings),
        height: _textHeight(),
        horizontalPadding: settings.margin,
      ),
    );
  }

  EpubReaderBackend _epubBackend(EpubBook book, ReaderSettings settings) {
    return EpubReaderBackend(
      book: book,
      paginator: TextPaginator(
        text: book.text,
        style: _readingTextStyle(settings),
        width: _textWidth(settings),
        height: _textHeight(),
        horizontalPadding: settings.margin,
      ),
    );
  }

  double _textWidth(ReaderSettings settings) {
    final double padding = settings.margin;
    // The reported viewport is already the page area: full width, height after
    // the reader bars. Only the horizontal margin is subtracted here, because
    // the text page applies exactly that margin and nothing vertically.
    return (_viewport.width - padding * 2).clamp(120.0, 4000.0);
  }

  double _textHeight() => _viewport.height.clamp(120.0, 4000.0);

  TextStyle _readingTextStyle(ReaderSettings settings) {
    return ReadingTextStyle.forReader(
      fontSizeScale: settings.fontSize,
      lineHeight: settings.lineHeight,
      serifFamily: ref.read(settingsProvider).appearance.serifReading
          ? kPaperSerifFamily
          : null,
    ).toTextStyle();
  }

  /// Supplies the laid-out viewport, which text pagination is measured
  /// against and which is not known until after the first frame.
  void setViewport(Size size) {
    if (size.isEmpty || size == _viewport) return;
    _viewport = size;
    final ReaderState? current = state.value;
    if (current == null) return;
    if (current.backend is! TextReaderBackend &&
        current.backend is! EpubReaderBackend) {
      return;
    }
    _repaginate(current.document);
  }

  /// Rebuilds the text backend after the user changed reader settings,
  /// keeping the current locator rather than a page number.
  void applyReaderSettings() {
    final ReaderState? current = state.value;
    if (current == null) return;
    if (current.backend is! TextReaderBackend &&
        current.backend is! EpubReaderBackend) {
      return;
    }
    _repaginate(current.document);
  }

  void _repaginate(Document document) {
    final ReaderState current = state.requireValue;
    final ReaderBackend previous = current.backend;
    final int keepPage = current.pageIndex;
    final String? keepLocator =
        current.scrollPosition?.locator ?? previous.currentLocator;
    final Duration carried = _elapsed();
    final ReaderSettings settings = ref.read(settingsProvider).reader;

    final ReaderBackend replacement;
    if (previous is EpubReaderBackend) {
      replacement = _epubBackend(previous.book, settings);
      bool restored = keepLocator != null && replacement is EpubReaderBackend
          ? replacement.goToLocator(keepLocator)
          : false;
      if (!restored) {
        unawaited(replacement.goToPage(keepPage));
      }
    } else {
      final String text = (previous as TextReaderBackend).paginator.text;
      replacement = _textBackend(document, text, settings);
      unawaited(replacement.goToPage(keepPage));
    }

    unawaited(previous.dispose());
    _backend = replacement;
    _accumulated = carried;
    _segmentStart = DateTime.now();

    ReadingPosition? scrollPosition;
    double? scrollRequest;
    if (settings.flow == ReaderFlow.scroll &&
        replacement is EpubReaderBackend) {
      final EpubReaderBackend epub = replacement;
      final double fraction = epub.fractionForLocator(epub.currentLocator);
      scrollPosition = ReadingPosition.atFraction(
        fraction,
        locator: epub.currentLocator,
      );
      scrollRequest = fraction;
      _scrollRequestId++;
    }

    _setState(
      ReaderState(
        document: document,
        backend: replacement,
        bookmarks: current.bookmarks,
        annotations: current.annotations,
        chromeVisible: current.chromeVisible,
        scrollPosition: scrollPosition,
        scrollRequestFraction: scrollRequest,
        scrollRequestId: _scrollRequestId,
      ),
    );
    _scheduleSave();
  }

  static int _pageForFraction(ReaderBackend backend, double fraction) {
    if (backend is TextReaderBackend) {
      return backend.paginator.pageForFraction(fraction);
    }
    if (backend is EpubReaderBackend) {
      return backend.pageForOffset(backend.offsetForFraction(fraction));
    }
    final int count = backend.pageCount;
    if (count <= 0) return 0;
    return (fraction.clamp(0.0, 1.0) * count).floor().clamp(0, count - 1);
  }

  // -------------------------------------------------------------- navigation

  void _notify() {
    final ReaderState? current = state.value;
    if (current != null) _setState(current.copyWith());
  }

  Future<void> goToPage(int index) async {
    final ReaderBackend? backend = _backend;
    if (backend == null) return;
    if (index < 0 || index >= backend.pageCount) return;
    await backend.goToPage(index);
    final ReaderState? current = state.value;
    if (current?.scrollPosition != null && backend is EpubReaderBackend) {
      final double fraction = backend.fractionForLocator(
        backend.currentLocator,
      );
      _setScrollState(
        fraction: fraction,
        locator: backend.currentLocator,
        requestScroll: true,
      );
    } else {
      _notify();
    }
    onInteraction();
    _scheduleSave();
  }

  Future<void> nextPage() async {
    final ReaderState? current = state.value;
    if (current?.scrollPosition != null &&
        current?.backend is EpubReaderBackend) {
      final double step = current!.pageCount <= 0
          ? 0.05
          : 1 / current.pageCount;
      _setScrollState(
        fraction: (current.progress + step).clamp(0.0, 1.0),
        requestScroll: true,
      );
      onInteraction();
      _scheduleSave();
      return;
    }
    final ReaderBackend? backend = _backend;
    if (backend == null) return;
    if (await backend.next()) {
      _notify();
      onInteraction();
      _scheduleSave();
    }
  }

  Future<void> previousPage() async {
    final ReaderState? current = state.value;
    if (current?.scrollPosition != null &&
        current?.backend is EpubReaderBackend) {
      final double step = current!.pageCount <= 0
          ? 0.05
          : 1 / current.pageCount;
      _setScrollState(
        fraction: (current.progress - step).clamp(0.0, 1.0),
        requestScroll: true,
      );
      onInteraction();
      _scheduleSave();
      return;
    }
    final ReaderBackend? backend = _backend;
    if (backend == null) return;
    if (await backend.previous()) {
      _notify();
      onInteraction();
      _scheduleSave();
    }
  }

  /// Opens a global text offset (TOC entry, search hit or annotation).
  Future<void> goToOffset(int offset) async {
    final ReaderBackend? backend = _backend;
    if (backend is! EpubReaderBackend) return;
    backend.goToOffset(offset);
    final ReaderState? current = state.value;
    if (current?.scrollPosition != null) {
      final double fraction = backend.book.text.isEmpty
          ? 0
          : (offset / backend.book.text.length).clamp(0.0, 1.0);
      _setScrollState(
        fraction: fraction,
        locator: backend.book.locatorAt(offset).toString(),
        requestScroll: true,
      );
    } else {
      _notify();
    }
    onInteraction();
    _scheduleSave();
  }

  Future<void> goToTocEntry(EpubTocEntry entry) async {
    final EpubReaderBackend? backend = epubBackend;
    final int? chapter = entry.chapterIndex;
    if (backend == null || chapter == null) return;
    await goToOffset(backend.book.globalOffset(chapter, entry.charOffset));
  }

  List<EpubTocEntry> get toc => epubBackend?.book.toc ?? const <EpubTocEntry>[];

  List<EpubSearchResult> search(String query, {int limit = 120}) =>
      epubBackend?.search(query, limit: limit) ?? const <EpubSearchResult>[];

  // ------------------------------------------------------------------ chrome

  void toggleChrome() {
    final ReaderState? current = state.value;
    if (current == null) return;
    _setState(current.copyWith(chromeVisible: !current.chromeVisible));
  }

  void showChrome() {
    final ReaderState? current = state.value;
    if (current == null || current.chromeVisible) return;
    _setState(current.copyWith(chromeVisible: true));
  }

  /// Records that the user did something, so an idle timer can flush progress.
  void onInteraction() {
    _idleSaveTimer?.cancel();
    _idleSaveTimer = Timer(PaperConfig.readerIdleSaveDelay, () {
      unawaited(_persist());
    });
  }

  // --------------------------------------------------------------- bookmarks

  Future<void> toggleBookmark() async {
    final ReaderState current = state.requireValue;
    final BookmarkRepository repository = ref.read(bookmarkRepositoryProvider);
    if (current.isBookmarked) {
      final Bookmark match = current.bookmarks.firstWhere(
        (Bookmark b) => b.pointsAt(current.position),
      );
      await repository.remove(match.id);
    } else {
      final EpubReaderBackend? epub = epubBackend;
      final String? chapterTitle = epub?.chapterTitleForLocator(
        current.position.locator,
      );
      await repository.add(
        documentId: documentId,
        position: current.position,
        excerpt: _excerptAt(current),
        chapterTitle: chapterTitle == null || chapterTitle.isEmpty
            ? null
            : chapterTitle,
        label: chapterTitle == null || chapterTitle.isEmpty
            ? null
            : chapterTitle,
      );
    }
    final List<Bookmark> bookmarks = await repository.listFor(documentId);
    _setState(current.copyWith(bookmarks: bookmarks));
  }

  Future<void> removeBookmark(String id) async {
    await ref.read(bookmarkRepositoryProvider).remove(id);
    final List<Bookmark> bookmarks = await ref
        .read(bookmarkRepositoryProvider)
        .listFor(documentId);
    final ReaderState current = state.requireValue;
    _setState(current.copyWith(bookmarks: bookmarks));
  }

  Future<void> goToBookmark(Bookmark bookmark) async {
    final ReaderBackend? backend = _backend;
    if (backend == null) return;
    final String? locator = bookmark.locator;
    if (locator != null &&
        backend is EpubReaderBackend &&
        backend.goToLocator(locator)) {
      final ReaderState? current = state.value;
      if (current?.scrollPosition != null) {
        final double fraction = backend.fractionForLocator(locator);
        _setScrollState(
          fraction: fraction,
          locator: locator,
          requestScroll: true,
        );
      } else {
        _notify();
      }
    } else if (bookmark.page >= 0) {
      await goToPage((bookmark.page - 1).clamp(0, backend.pageCount - 1));
    } else {
      await goToPage(_pageForFraction(backend, bookmark.fraction));
    }
    onInteraction();
    _scheduleSave();
  }

  String? _excerptAt(ReaderState current) {
    final ReaderBackend backend = current.backend;
    if (backend is EpubReaderBackend) {
      if (current.scrollPosition != null) {
        final EpubLocator? locator = EpubLocator.tryParse(
          current.position.locator,
        );
        if (locator == null) return null;
        final EpubChapter? chapter = backend.book.chapterAt(locator.spineIndex);
        if (chapter == null) return null;
        final int start = locator.charOffset.clamp(0, chapter.text.length);
        final int end = (start + 90).clamp(start, chapter.text.length);
        final String excerpt = chapter.text
            .substring(start, end)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        return excerpt.isEmpty ? null : '$excerpt…';
      }
      final String text = backend.currentPage.text
          .split('\n')
          .map((String line) => line.trim())
          .firstWhere((String line) => line.isNotEmpty, orElse: () => '');
      return text.length <= 90 ? text : '${text.substring(0, 89)}…';
    }
    if (backend is! TextReaderBackend) return null;
    final String firstLine = backend.paginator
        .pageAt(current.pageIndex)
        .text
        .split('\n')
        .map((String line) => line.trim())
        .firstWhere((String line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return null;
    return firstLine.length <= 90
        ? firstLine
        : '${firstLine.substring(0, 89)}…';
  }

  // ------------------------------------------------------------- annotations

  Future<Annotation?> addAnnotation({
    required AnnotationKind kind,
    required int start,
    required int end,
    String? note,
  }) async {
    final EpubReaderBackend? backend = epubBackend;
    if (backend == null) return null;
    final EpubSelection? selection = backend.selectionFor(start, end);
    if (selection == null) {
      throw const PaperException.corruptDocument(
        'That passage could not be anchored. Try selecting a shorter phrase.',
      );
    }
    final Annotation annotation = await ref
        .read(annotationRepositoryProvider)
        .add(
          documentId: documentId,
          kind: kind,
          startLocator: selection.startLocator,
          endLocator: selection.endLocator,
          chapterIndex: selection.chapterIndex,
          chapterTitle: selection.chapterTitle,
          excerpt: selection.excerpt,
          note: note,
        );
    await _refreshAnnotations();
    return annotation;
  }

  Future<void> updateAnnotationNote(String id, String? note) async {
    await ref.read(annotationRepositoryProvider).updateNote(id, note);
    await _refreshAnnotations();
  }

  Future<void> deleteAnnotation(String id) async {
    await ref.read(annotationRepositoryProvider).remove(id);
    await _refreshAnnotations();
  }

  Future<void> goToAnnotation(Annotation annotation) async {
    final EpubReaderBackend? backend = epubBackend;
    if (backend == null) return;
    final ({int start, int end})? range = backend.annotationRange(annotation);
    if (range == null) {
      await ref.read(annotationRepositoryProvider).markOrphaned(annotation.id);
      await _refreshAnnotations();
      return;
    }
    await goToOffset(range.start);
  }

  Future<void> _refreshAnnotations() async {
    final List<Annotation> annotations = await ref
        .read(annotationRepositoryProvider)
        .listFor(documentId);
    final ReaderState? current = state.value;
    if (current == null) return;
    _setState(current.copyWith(annotations: annotations));
  }

  // --------------------------------------------------------------- scrolling

  /// Called by the EPUB scroll surface as the user moves through the book.
  /// [fraction] is a position in the extracted text, not a page ratio.
  void setScrollFraction(double fraction) {
    final ReaderBackend? backend = _backend;
    if (backend is! EpubReaderBackend) return;
    final double clamped = fraction.clamp(0.0, 1.0);
    final ReaderState? current = state.value;
    if (current == null) return;
    final double previous = current.scrollPosition?.fraction ?? -1;
    if ((previous - clamped).abs() < 0.0002) return;
    final int offset = backend.offsetForFraction(clamped);
    _setScrollState(
      fraction: clamped,
      locator: backend.book.locatorAt(offset).toString(),
    );
    onInteraction();
    _scheduleSave();
  }

  void _setScrollState({
    required double fraction,
    String? locator,
    bool requestScroll = false,
  }) {
    final ReaderState? current = state.value;
    if (current == null) return;
    final ReadingPosition position = ReadingPosition.atFraction(
      fraction.clamp(0.0, 1.0),
      locator: locator ?? current.position.locator,
    );
    if (requestScroll) _scrollRequestId++;
    _setState(
      current.copyWith(
        scrollPosition: position,
        scrollRequestFraction: requestScroll ? fraction : null,
        scrollRequestId: requestScroll ? _scrollRequestId : null,
      ),
    );
  }

  void clearScrollOverride() {
    final ReaderState? current = state.value;
    if (current == null) return;
    _setState(current.copyWith(clearScrollPosition: true));
  }

  // ------------------------------------------------------------- persistence

  Duration _elapsed() {
    final DateTime? start = _segmentStart;
    if (start == null) return _accumulated;
    return _accumulated + DateTime.now().difference(start);
  }

  void _scheduleSave() {
    if (_backend == null || state.value == null) return;
    _saveDebouncer.run(() => unawaited(_persist()));
  }

  /// Writes reading progress.
  ///
  /// Failures are swallowed on purpose: losing a position update is a far
  /// smaller harm than interrupting a reading session, and the next write
  /// carries the same information.
  Future<void> _persist({bool closeSegment = false}) async {
    final ReaderBackend? backend = _backend;
    final ReaderState? current = state.value;
    final DocumentRepository? documents = _documents;
    if (backend == null || current == null || documents == null) return;
    await _writeProgress(current, documents, closeSegment: closeSegment);
  }

  /// Writes a captured state through a captured repository.
  ///
  /// Kept free of `ref` and provider `state` so it remains safe to call from the
  /// provider's disposal callback, where Riverpod forbids both.
  Future<void> _writeProgress(
    ReaderState current,
    DocumentRepository documents, {
    required bool closeSegment,
  }) async {
    _saveDebouncer.cancel();
    final Duration elapsed = _elapsed();
    if (closeSegment) {
      _segmentStart = null;
      _accumulated = Duration.zero;
    } else {
      _segmentStart = DateTime.now();
      _accumulated = Duration.zero;
    }

    try {
      await documents.saveProgress(
        id: documentId,
        position: current.position,
        pageCount: current.pageCount,
        maxPageSeen: current.position.page ?? (current.pageIndex + 1),
        sessionLength: elapsed,
      );
    } on PaperException {
      // Intentionally ignored. A lost position update is a smaller harm than
      // interrupting a reading session; the next write carries the same state.
    }
  }
}

final readerProvider = AsyncNotifierProvider.autoDispose
    .family<ReaderSession, ReaderState, String>(
      ReaderSession.new,
      // Opening a local document is deterministic. Retrying a corrupt EPUB or
      // a missing file leaves the screen loading forever instead of showing the
      // recoverable error the reader has already prepared.
      retry: (int retryCount, Object error) => null,
    );
