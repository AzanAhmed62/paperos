import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// A measured slice of a continuous text document.
class TextPage {
  const TextPage({required this.start, required this.end, required this.text});

  /// Character offset of the first character on the page.
  final int start;

  /// Exclusive character offset just past the last character.
  final int end;

  final String text;

  int get length => end - start;

  bool get isEmpty => text.trim().isEmpty;

  @override
  String toString() => 'TextPage($start..$end)';
}

/// Lays a continuous text document out into pages that exactly fit the
/// viewport.
///
/// Design notes:
///
///  * **Measured, not estimated.** Every page boundary comes from a real
///    [TextPainter] layout, so a page never overflows and never leaves a third
///    of the screen blank. Estimates are only used to seed the search.
///  * **Lazy.** Boundaries are produced forward on demand and cached. Opening a
///    500-page book costs one measurement, not five hundred.
///  * **Page oriented.** Page numbers are the unit of navigation, progress and
///    bookmarks, which is what makes the text reader feel like the PDF reader
///    instead of like a scrolling web view.
class TextPaginator {
  TextPaginator({
    required this.text,
    required this.style,
    required this.width,
    required this.height,
    this.horizontalPadding = 0,
    this.textScaler = TextScaler.noScaling,
  }) : assert(width > 0 && height > 0, 'Viewport must have a positive size') {
    _painter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      textScaler: textScaler,
      strutStyle: StrutStyle(
        fontFamily: style.fontFamily,
        fontSize: style.fontSize,
        height: style.height,
        forceStrutHeight: false,
      ),
    );
  }

  final String text;
  final TextStyle style;

  /// Usable text width in logical pixels.
  final double width;

  /// Usable text height in logical pixels.
  final double height;
  final double horizontalPadding;

  /// The same scaler the reading surface renders with. Measuring with
  /// [TextScaler.noScaling] while the text draws with the system font scale is
  /// what makes large accessibility text overflow its measured page.
  final TextScaler textScaler;

  late final TextPainter _painter;

  /// Start offset of every page materialised so far.
  final List<int> _starts = <int>[0];

  int _lastEnd = 0;
  bool _complete = false;

  /// Characters that fit in one page, calibrated on first use.
  int? _charsPerPage;

  /// Number of pages discovered so far.
  int get materializedPages => _starts.length;

  /// True once the final page boundary is known.
  bool get isComplete => _complete;

  /// Total pages. Exact only when [isComplete]; otherwise an estimate derived
  /// from the measured characters-per-page, which is accurate to a few percent
  /// for uniform prose and clearly labelled as an estimate in the UI.
  int get pageCount {
    if (_complete) return _starts.length;
    final int chars = _calibrate();
    if (chars <= 0) return 1;
    return math.max(1, (text.length / chars).ceil());
  }

  bool get isEmptyDocument => text.trim().isEmpty;

  /// 0..1 progress of [index] within [pageCount].
  double fractionFor(int index, {int? total}) {
    final int count = total ?? pageCount;
    if (count <= 1) return index <= 0 ? 0 : 1;
    return (index / count).clamp(0.0, 1.0);
  }

  /// Page index for a 0..1 fraction.
  int pageForFraction(double fraction, {int? total}) {
    final int count = total ?? pageCount;
    if (count <= 0) return 0;
    return (fraction.clamp(0.0, 1.0) * count).floor().clamp(0, count - 1);
  }

  /// The page at [index], materialising boundaries up to it if needed.
  TextPage pageAt(int index) {
    if (text.isEmpty) {
      return const TextPage(start: 0, end: 0, text: '');
    }
    // Ask for one boundary beyond [index]: a page is only bounded once the
    // *start of the next page* is known. Without this, the first request would
    // fall back to "rest of the document" and the reader would draw the whole
    // book on page one.
    _materialise(index + 1);
    final int clamped = index.clamp(0, _starts.length - 1);
    final int start = _starts[clamped];
    final int end = clamped + 1 < _starts.length
        ? _starts[clamped + 1]
        : (_complete ? _lastEnd : text.length);
    final int safeEnd = end.clamp(start, text.length);
    return TextPage(
      start: start,
      end: safeEnd,
      text: text.substring(start, safeEnd),
    );
  }

  void _materialise(int index) {
    int guard = 0;
    while (_starts.length <= index && !_complete && guard < 100000) {
      _extend();
      guard++;
    }
  }

  void _extend() {
    final int start = _starts.last;
    if (start >= text.length) {
      _complete = true;
      return;
    }
    final int end = _findEnd(start);
    _lastEnd = end;
    if (end >= text.length) {
      _complete = true;
      return;
    }
    _starts.add(end);
  }

  // ------------------------------------------------------------------ layout

  bool _fits(int start, int end) {
    if (end <= start) return true;
    _painter.text = TextSpan(text: text.substring(start, end), style: style);
    _painter.layout(maxWidth: width);
    return _painter.height <= height;
  }

  /// Measures a sample window to estimate how many characters fit on a page.
  int _calibrate() {
    final int? cached = _charsPerPage;
    if (cached != null && cached > 0) return cached;

    // ~24 lines is enough to average out paragraph breaks and long words.
    const int sampleChars = 2400;
    final int end = math.min(text.length, sampleChars);
    if (end <= 0) {
      _charsPerPage = 1;
      return 1;
    }
    _painter.text = TextSpan(text: text.substring(0, end), style: style);
    _painter.layout(maxWidth: width);
    final double lines = math.max(1.0, _painter.height / _lineHeight());
    final double charsPerLine = end / lines;
    final int estimate = math.max(1, (charsPerLine * _linesPerPage()).round());
    _charsPerPage = estimate;
    return estimate;
  }

  double _lineHeight() {
    final double size = style.fontSize ?? 14;
    return size * (style.height ?? 1.2);
  }

  int _linesPerPage() {
    final double lines = height / _lineHeight();
    return math.max(1, lines.floor());
  }

  /// Largest end offset such that `text[start..end)` fits the viewport, snapped
  /// to a paragraph or line break when one is close enough to the boundary to
  /// avoid leaving a visibly short page.
  int _findEnd(int start) {
    final int n = text.length;
    if (start >= n) return n;

    // Final page: the whole remainder fits.
    if (_fits(start, n)) return n;

    final int minimum = math.min(n, start + 1);
    int low = minimum;
    int high = math.min(n, start + _calibrate());

    // Grow until `high` provably overflows.
    int guard = 0;
    while (high < n && _fits(start, high) && guard < 12) {
      low = high;
      high = math.min(n, high + math.max(1, (high - start) ~/ 2));
      guard++;
    }
    if (high >= n) high = n - 1;
    if (high <= low) return low;

    // Binary search for the largest fitting end.
    while (low + 1 < high) {
      final int mid = low + ((high - low) >> 1);
      if (_fits(start, mid)) {
        low = mid;
      } else {
        high = mid;
      }
    }

    return _snapToBreak(start, low);
  }

  /// Prefers to end a page at a paragraph break (blank line) and, failing
  /// that, at a line break, so text does not get cut mid-sentence.
  int _snapToBreak(int start, int end) {
    if (end >= text.length) return end;
    final int span = end - start;
    if (span < 8) return end;

    final int paragraph = text.lastIndexOf('\n\n', end - 1);
    if (paragraph > start + (span * 4) ~/ 10) return paragraph + 2;

    final int line = text.lastIndexOf('\n', end - 1);
    if (line > start + (span * 8) ~/ 10) return line + 1;

    return end;
  }

  void dispose() => _painter.dispose();
}

/// The typography a text document is read with, derived from user settings.
///
/// Kept separate from the paginator so that a settings change produces a new
/// paginator rather than mutating one in place.
class ReadingTextStyle {
  const ReadingTextStyle({
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
  });

  factory ReadingTextStyle.forReader({
    required double fontSizeScale,
    required double lineHeight,
    required String? serifFamily,
  }) {
    return ReadingTextStyle(
      fontSize: 18.5 * fontSizeScale,
      lineHeight: lineHeight,
      fontFamily: serifFamily,
    );
  }

  final double fontSize;
  final double lineHeight;
  final String? fontFamily;

  TextStyle toTextStyle() {
    return TextStyle(
      fontSize: fontSize,
      height: lineHeight,
      fontFamily: fontFamily,
      color: const Color(0xFF000000),
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }
}
