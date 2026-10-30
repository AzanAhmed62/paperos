import 'package:flutter/foundation.dart';

import '../../../core/platform/pdf_service.dart';
import '../../annotations/domain/annotation.dart';
import '../../library/domain/document.dart';
import 'text_paginator.dart';

/// Which rendering engine is driving the reader.
enum ReaderFormat { pdf, text, epub }

/// The format-specific half of a reading session.
///
/// [ReaderController] owns everything that is the same for every format —
/// progress persistence, bookmarks, chrome, error reporting — and delegates
/// the rest here. Adding EPUB later means one new implementation of this
/// interface and no changes to the reader shell.
abstract interface class ReaderBackend {
  ReaderFormat get format;

  /// Total pages. For continuous documents this is the paginated page count,
  /// which is exact once the document has been read to the end.
  int get pageCount;

  /// 0-based index of the page on screen.
  int get pageIndex;

  /// Whether the page count is a measured value or an estimate.
  bool get isPageCountExact;

  /// 0..1 progress.
  double get progress;

  /// Format-native locator for the current position, when the format has one.
  String? get currentLocator;

  /// Position as a fraction of the document's extracted text, independent of
  /// pagination. Scroll mode uses this to restore a truthful place.
  double get textFraction;

  /// Short position string, e.g. "Page 12 of 340" or "12% · page 4 of ~90".
  String get positionLabel;

  /// Aspect ratio of the rendered page, or null when the format has none.
  double? get pageAspectRatio;

  Future<void> goToPage(int index);

  Future<bool> next();

  Future<bool> previous();

  /// Releases platform resources. After this the backend is unusable.
  Future<void> dispose();
}

/// Reads a PDF through the platform's `PdfRenderer`.
///
/// Holds no page bitmaps: pages are rendered on demand, cached by the reader
/// widget for a couple of pages, and dropped again. A 900-page scanned book
/// therefore costs roughly one screen of memory, not the whole file.
class PdfReaderBackend implements ReaderBackend {
  PdfReaderBackend(this._handle, this._pdf);

  final PdfDocumentHandle _handle;
  final PdfService _pdf;
  bool _disposed = false;

  /// Identifier the platform uses to address the open file. The reader widget
  /// needs it to ask for a page bitmap.
  String get handleId => _handle.handle;

  @override
  ReaderFormat get format => ReaderFormat.pdf;

  @override
  int get pageCount => _handle.pageCount;

  int _index = 0;

  @override
  int get pageIndex => _index;

  @override
  bool get isPageCountExact => true;

  @override
  double get progress {
    if (_handle.pageCount <= 0) return 0;
    return ((_index + 1) / _handle.pageCount).clamp(0.0, 1.0);
  }

  @override
  String? get currentLocator => null;

  @override
  double get textFraction => progress;

  @override
  String get positionLabel => _handle.pageCount > 0
      ? 'Page ${_index + 1} of ${_handle.pageCount}'
      : 'Page ${_index + 1}';

  @override
  double? get pageAspectRatio => _handle.pageHeightPt > 0
      ? _handle.pageWidthPt / _handle.pageHeightPt
      : null;

  @override
  Future<void> goToPage(int index) async {
    _index = index.clamp(0, _handle.pageCount - 1);
  }

  @override
  Future<bool> next() async {
    if (_index >= _handle.pageCount - 1) return false;
    _index++;
    return true;
  }

  @override
  Future<bool> previous() async {
    if (_index <= 0) return false;
    _index--;
    return true;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _pdf.close(_handle.handle);
  }
}

/// Reads a plain text file as a paginated book.
class TextReaderBackend implements ReaderBackend {
  TextReaderBackend({required this.paginator, required this.title});

  final TextPaginator paginator;
  final String title;

  int _index = 0;

  @override
  ReaderFormat get format => ReaderFormat.text;

  @override
  int get pageCount => paginator.pageCount;

  @override
  int get pageIndex => _index;

  @override
  bool get isPageCountExact => paginator.isComplete;

  @override
  double get progress =>
      paginator.fractionFor(_index, total: paginator.pageCount);

  @override
  String? get currentLocator => null;

  @override
  double get textFraction => progress;

  @override
  String get positionLabel {
    final String page = 'Page ${_index + 1}';
    if (paginator.isComplete) return '$page of ${paginator.pageCount}';
    return '$page · about ${paginator.pageCount} pages';
  }

  @override
  double? get pageAspectRatio => null;

  @override
  Future<void> goToPage(int index) async {
    _index = index.clamp(0, paginator.pageCount - 1);
    // Force the boundary to exist so the very next frame can draw it.
    paginator.pageAt(_index);
  }

  @override
  Future<bool> next() async {
    if (_index >= paginator.pageCount - 1) return false;
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
}

/// Immutable snapshot of a reading session, held in the Riverpod state.
///
/// Keeping the session as a value object (rather than letting widgets read a
/// mutable controller) is what lets the reader UI rebuild only the parts that
/// changed and keeps navigation testable.
@immutable
class ReaderState {
  const ReaderState({
    required this.document,
    required this.backend,
    required this.bookmarks,
    this.annotations = const <Annotation>[],
    this.chromeVisible = true,
    this.scrollPosition,
    this.scrollRequestFraction,
    this.scrollRequestId = 0,
  });

  final Document document;
  final ReaderBackend backend;
  final List<Bookmark> bookmarks;
  final List<Annotation> annotations;
  final bool chromeVisible;

  /// Set while the EPUB scroll surface is active. Paged position and scroll
  /// position are mutually exclusive; the latter wins when present.
  final ReadingPosition? scrollPosition;

  /// A one-shot instruction for the scroll surface: jump to this fraction.
  final double? scrollRequestFraction;
  final int scrollRequestId;

  int get pageIndex => backend.pageIndex;
  int get pageCount => backend.pageCount;
  double get progress => scrollPosition?.fraction ?? backend.progress;
  String get positionLabel {
    if (scrollPosition != null && backend.format == ReaderFormat.epub) {
      final int percent = (progress.clamp(0.0, 1.0) * 100).round();
      return '$percent%';
    }
    return backend.positionLabel;
  }

  /// The stored position for the page currently on screen.
  ReadingPosition get position {
    final ReadingPosition? scrolled = scrollPosition;
    if (scrolled != null) return scrolled;
    final int page = backend.pageIndex + 1;
    if (backend.format == ReaderFormat.pdf) {
      return ReadingPosition.atPage(page);
    }
    if (backend.format == ReaderFormat.epub) {
      return ReadingPosition(
        page: page,
        fraction: backend.progress,
        locator: backend.currentLocator,
      );
    }
    // Continuous text stores the page index as the authoritative locator and
    // the fraction alongside it, so that a resume never has to guess.
    return ReadingPosition(page: page, fraction: backend.progress);
  }

  /// Fraction at which a freshly opened scroll surface should start.
  double get initialScrollFraction =>
      scrollPosition?.fraction ?? backend.textFraction;

  bool get isBookmarked => bookmarks.any((Bookmark b) => b.pointsAt(position));

  ReaderState copyWith({
    List<Bookmark>? bookmarks,
    List<Annotation>? annotations,
    bool? chromeVisible,
    ReadingPosition? scrollPosition,
    bool clearScrollPosition = false,
    double? scrollRequestFraction,
    int? scrollRequestId,
  }) {
    return ReaderState(
      document: document,
      backend: backend,
      bookmarks: bookmarks ?? this.bookmarks,
      annotations: annotations ?? this.annotations,
      chromeVisible: chromeVisible ?? this.chromeVisible,
      scrollPosition: clearScrollPosition
          ? null
          : scrollPosition ?? this.scrollPosition,
      scrollRequestFraction:
          scrollRequestFraction ?? this.scrollRequestFraction,
      scrollRequestId: scrollRequestId ?? this.scrollRequestId,
    );
  }
}
