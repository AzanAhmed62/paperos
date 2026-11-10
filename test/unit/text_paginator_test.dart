import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/features/reader/domain/text_paginator.dart';

/// The paginator measures with a real [TextPainter], so it needs a live
/// binding. The Flutter test font gives every glyph the same advance width,
/// which is exactly what a pagination test wants: predictable, geometry-only
/// behaviour with no font-loading flakiness.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const TextStyle style = TextStyle(fontSize: 16, height: 1.5);
  const String prose =
      'PaperOS keeps the reading surface quiet so the page is the only thing '
      'that competes for attention. ';

  TextPaginator paginate({
    required String text,
    double width = 400,
    double height = 600,
    double horizontalPadding = 0,
  }) {
    return TextPaginator(
      text: text,
      style: style,
      width: width,
      height: height,
      horizontalPadding: horizontalPadding,
    );
  }

  /// Walks the paginator to the very end the way the reader does when the user
  /// reaches the last page. `pageCount` before this point is an estimate and
  /// may overshoot, so tests must never loop over it and assume gapless pages.
  List<TextPage> readToEnd(TextPaginator paginator) {
    final List<TextPage> pages = <TextPage>[];
    int index = 0;
    while (true) {
      final TextPage page = paginator.pageAt(index);
      if (pages.isNotEmpty && page.start == pages.last.start) break;
      pages.add(page);
      if (paginator.isComplete && page.end >= paginator.text.length) break;
      index++;
      if (index > 100000) {
        fail('paginator never completed');
      }
    }
    return pages;
  }

  group('TextPaginator', () {
    test('treats an empty document as a single blank page', () {
      final TextPaginator paginator = paginate(text: '');

      expect(paginator.isEmptyDocument, isTrue);
      expect(paginator.pageCount, 1);

      final TextPage page = paginator.pageAt(0);
      expect(page.text, isEmpty);
      expect(page.start, 0);
      expect(page.end, 0);
    });

    test('treats whitespace-only input as empty rather than paginating it', () {
      final TextPaginator paginator = paginate(text: '   \n\n  ');

      expect(paginator.isEmptyDocument, isTrue);
      expect(paginator.pageCount, 1);
    });

    test('keeps a short document on one page', () {
      final TextPaginator paginator = paginate(text: 'One short page.');

      final List<TextPage> pages = readToEnd(paginator);
      expect(pages, hasLength(1));
      expect(paginator.isComplete, isTrue);
      expect(paginator.pageCount, 1);
    });

    test('splits long text into consecutive, gapless pages', () {
      final TextPaginator paginator = paginate(text: prose * 400);

      final List<TextPage> pages = readToEnd(paginator);
      expect(pages.length, greaterThan(1));
      expect(paginator.isComplete, isTrue);

      // Every page starts exactly where the previous one ended: no dropped
      // characters and no duplicated ones.
      int expectedStart = 0;
      for (int index = 0; index < pages.length; index++) {
        final TextPage page = pages[index];
        expect(page.start, expectedStart, reason: 'page $index starts wrong');
        expect(
          page.end,
          greaterThan(page.start),
          reason: 'page $index is empty',
        );
        expectedStart = page.end;
      }
      expect(expectedStart, paginator.text.length);
    });

    test('covers the whole document across its pages', () {
      final String text = prose * 250;
      final TextPaginator paginator = paginate(text: text);

      final String rebuilt = readToEnd(paginator)
          .map((TextPage page) => page.text)
          .join();

      expect(
        rebuilt,
        text,
        reason: 'pages must reconstruct the source exactly',
      );
    });

    test('measures with the text scale the reader draws with', () {
      final TextPaginator standard = paginate(text: prose * 400);
      final TextPaginator scaled = TextPaginator(
        text: prose * 400,
        style: style,
        width: 400,
        height: 600,
        textScaler: const TextScaler.linear(2),
      );

      // A page measured at 200% type must hold fewer characters than the same
      // page at 100%, otherwise large accessibility text would overflow.
      expect(scaled.pageAt(0).end, lessThan(standard.pageAt(0).end));
    });

    test('measures lazily and finishes only when the end is reached', () {
      final TextPaginator paginator = paginate(text: prose * 1000);

      // Just calibration: opening a long book must not lay the whole thing out.
      expect(paginator.materializedPages, 1);
      expect(paginator.isComplete, isFalse);

      // Drawing page 0 needs page 0's *end*, which is the start of page 1, so
      // exactly one further boundary is measured. No more.
      paginator.pageAt(0);
      expect(paginator.materializedPages, 2);
      expect(paginator.isComplete, isFalse);

      // The whole book is still not laid out.
      expect(paginator.materializedPages, lessThan(50));

      readToEnd(paginator);
      expect(paginator.isComplete, isTrue);
    });

    test('clamps out-of-range page requests instead of throwing', () {
      final TextPaginator paginator = paginate(text: prose * 60);
      final List<TextPage> pages = readToEnd(paginator);

      expect(paginator.pageAt(-5).start, pages.first.start);
      expect(paginator.pageAt(9999).start, pages.last.start);
      expect(paginator.pageAt(9999).end, paginator.text.length);
    });

    test('page count grows when the viewport shrinks', () {
      final String text = prose * 300;
      final TextPaginator tall = paginate(text: text, height: 800);
      final TextPaginator short = paginate(text: text, height: 300);

      expect(readToEnd(short).length, greaterThan(readToEnd(tall).length));
    });

    test('a wider viewport never needs more pages than a narrow one', () {
      final String text = prose * 300;
      final TextPaginator narrow = paginate(text: text, width: 260);
      final TextPaginator wide = paginate(text: text, width: 900);

      expect(
        readToEnd(wide).length,
        lessThanOrEqualTo(readToEnd(narrow).length),
      );
    });
  });

  group('TextPaginator fractions', () {
    test('maps page numbers onto 0..1', () {
      final TextPaginator paginator = paginate(text: prose * 200);

      expect(paginator.fractionFor(0, total: 10), 0);
      expect(paginator.fractionFor(5, total: 10), closeTo(0.5, 0.001));
      expect(paginator.fractionFor(10, total: 10), closeTo(1.0, 0.001));
    });

    test(
      'a single-page document is either beginning or end, never in between',
      () {
        final TextPaginator paginator = paginate(text: 'Short.');

        expect(paginator.fractionFor(0, total: 1), 0);
        expect(paginator.fractionFor(1, total: 1), 1);
      },
    );

    test('resolves a fraction back to a page inside the document', () {
      final TextPaginator paginator = paginate(text: prose * 200);
      final int total = readToEnd(paginator).length;

      for (int page = 0; page < total; page++) {
        final int resolved = paginator.pageForFraction(
          paginator.fractionFor(page, total: total),
          total: total,
        );
        expect(resolved, page);
      }
    });

    test('clamps nonsense fractions instead of returning a bad page', () {
      final TextPaginator paginator = paginate(text: prose * 40);
      final int total = readToEnd(paginator).length;

      expect(paginator.pageForFraction(-3, total: total), 0);
      expect(paginator.pageForFraction(7.5, total: total), total - 1);
    });
  });
}
