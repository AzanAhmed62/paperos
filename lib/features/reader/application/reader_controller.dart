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
import '../../library/data/bookmark_repository.dart';
import '../../library/domain/document.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/app_settings.dart';
import '../domain/reader_backend.dart';
import '../domain/text_paginator.dart';

/// One reading session.
///
/// Owns the backend, the current page, the bookmark list and the write-behind
/// progress store. Everything format specific lives behind [ReaderBackend], so
/// this class behaves identically for a PDF and for a text file — and adding a
/// third format later does not touch it.
class ReaderSession extends AsyncNotifier<ReaderState> {
  /// Injected by the family constructor.
  ReaderSession(this.documentId);

  final String documentId;

  ReaderBackend? _backend;
  final Debouncer _saveDebouncer = Debouncer(
    delay: PaperConfig.progressWriteDebounce,
  );

  DateTime? _segmentStart;
  Duration _accumulated = Duration.zero;
  Timer? _idleSaveTimer;
  Size _viewport = Size.zero;

  @override
  Future<ReaderState> build() async {
    ref.onDispose(() {
      _idleSaveTimer?.cancel();
      _saveDebouncer.cancel();
      // Deliberately not awaited: a progress write must not delay the frame in
      // which the reader is torn down.
      unawaited(_persist(closeSegment: true));
      final ReaderBackend? backend = _backend;
      _backend = null;
      if (backend != null) unawaited(backend.dispose());
    });

    final Document? stored = await ref
        .watch(documentRepositoryProvider)
        .findById(documentId);
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

    final ReadingPosition? saved = document.progress.position;
    var startIndex = 0;
    if (saved != null) {
      startIndex = saved.page != null
          ? (saved.page! - 1).clamp(0, backend.pageCount - 1)
          : _pageForFraction(backend, saved.fraction ?? 0);
    }
    await backend.goToPage(startIndex);

    _backend = backend;
    _segmentStart = DateTime.now();
    _accumulated = Duration.zero;

    final List<Bookmark> bookmarks = await ref
        .read(bookmarkRepositoryProvider)
        .listFor(documentId);

    return ReaderState(
      document: document,
      backend: backend,
      bookmarks: bookmarks,
    );
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

    throw PaperException.unsupportedFormat(
      'PaperOS does not open ${document.format.label} files yet.',
    );
  }

  TextReaderBackend _textBackend(
    Document document,
    String text,
    ReaderSettings settings,
  ) {
    final double padding = settings.margin;
    // The reported viewport is already the page area: full width, height after
    // the reader bars. Only the horizontal margin is subtracted here, because
    // the text page applies exactly that margin and nothing vertically.
    final double width = (_viewport.width - padding * 2).clamp(120.0, 4000.0);
    final double height = _viewport.height.clamp(120.0, 4000.0);

    return TextReaderBackend(
      title: document.title,
      paginator: TextPaginator(
        text: text,
        style: _readingTextStyle(settings),
        width: width,
        height: height,
        horizontalPadding: padding,
      ),
    );
  }

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
    if (current == null || current.backend is! TextReaderBackend) return;
    _repaginate(current.document);
  }

  /// Rebuilds the text backend after the user changed reader settings,
  /// keeping the current page number.
  void applyReaderSettings() {
    final ReaderState? current = state.value;
    if (current == null || current.backend is! TextReaderBackend) return;
    _repaginate(current.document);
  }

  void _repaginate(Document document) {
    final ReaderState current = state.requireValue;
    final TextReaderBackend previous = current.backend as TextReaderBackend;
    final String text = previous.paginator.text;
    final int keepPage = current.pageIndex;
    final Duration carried = _elapsed();
    previous.dispose();

    final TextReaderBackend replacement = _textBackend(
      document,
      text,
      ref.read(settingsProvider).reader,
    );
    _backend = replacement;
    _accumulated = carried;
    _segmentStart = DateTime.now();
    unawaited(replacement.goToPage(keepPage));

    state = AsyncData(
      ReaderState(
        document: document,
        backend: replacement,
        bookmarks: current.bookmarks,
        chromeVisible: current.chromeVisible,
      ),
    );
    _scheduleSave();
  }

  static int _pageForFraction(ReaderBackend backend, double fraction) {
    if (backend is TextReaderBackend) {
      return backend.paginator.pageForFraction(fraction);
    }
    final int count = backend.pageCount;
    if (count <= 0) return 0;
    return (fraction.clamp(0.0, 1.0) * count).floor().clamp(0, count - 1);
  }

  // -------------------------------------------------------------- navigation

  Future<void> goToPage(int index) async {
    final ReaderBackend? backend = _backend;
    if (backend == null) return;
    if (index < 0 || index >= backend.pageCount) return;
    await backend.goToPage(index);
    onInteraction();
    _scheduleSave();
  }

  Future<void> nextPage() async {
    final ReaderBackend? backend = _backend;
    if (backend == null) return;
    if (await backend.next()) {
      onInteraction();
      _scheduleSave();
    }
  }

  Future<void> previousPage() async {
    final ReaderBackend? backend = _backend;
    if (backend == null) return;
    if (await backend.previous()) {
      onInteraction();
      _scheduleSave();
    }
  }

  // ------------------------------------------------------------------ chrome

  void toggleChrome() {
    final ReaderState? current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(chromeVisible: !current.chromeVisible));
  }

  void showChrome() {
    final ReaderState? current = state.value;
    if (current == null || current.chromeVisible) return;
    state = AsyncData(current.copyWith(chromeVisible: true));
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
      await repository.add(
        documentId: documentId,
        position: current.position,
        excerpt: _excerptAt(current),
      );
    }
    final List<Bookmark> bookmarks = await repository.listFor(documentId);
    state = AsyncData(current.copyWith(bookmarks: bookmarks));
  }

  Future<void> removeBookmark(String id) async {
    await ref.read(bookmarkRepositoryProvider).remove(id);
    final List<Bookmark> bookmarks = await ref
        .read(bookmarkRepositoryProvider)
        .listFor(documentId);
    final ReaderState current = state.requireValue;
    state = AsyncData(current.copyWith(bookmarks: bookmarks));
  }

  Future<void> goToBookmark(Bookmark bookmark) async {
    final ReaderBackend? backend = _backend;
    if (backend == null) return;
    if (bookmark.page >= 0) {
      await goToPage((bookmark.page - 1).clamp(0, backend.pageCount - 1));
    } else {
      await goToPage(_pageForFraction(backend, bookmark.fraction));
    }
  }

  String? _excerptAt(ReaderState current) {
    final ReaderBackend backend = current.backend;
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
    if (backend == null || current == null) return;

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
      await ref
          .read(documentRepositoryProvider)
          .saveProgress(
            id: documentId,
            position: current.position,
            pageCount: current.pageCount,
            maxPageSeen: current.pageIndex + 1,
            sessionLength: elapsed,
          );
    } on PaperException {
      // Intentionally ignored. See the doc comment.
    }
  }
}

final readerProvider = AsyncNotifierProvider.autoDispose
    .family<ReaderSession, ReaderState, String>(ReaderSession.new);
