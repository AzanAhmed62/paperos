import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/features/annotations/domain/annotation.dart';
import 'package:paperos/features/reader/domain/text_paginator.dart';
import 'package:paperos/features/reader/epub/epub_book.dart';
import 'package:paperos/features/reader/epub/epub_parser.dart';
import 'package:paperos/features/reader/epub/epub_reader_backend.dart';

import '../support/epub_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EpubBook book;
  late EpubReaderBackend backend;

  EpubReaderBackend makeBackend({double width = 320, double height = 420}) {
    return EpubReaderBackend(
      book: book,
      paginator: TextPaginator(
        text: book.text,
        style: const TextStyle(fontSize: 16, height: 1.5),
        width: width,
        height: height,
      ),
    );
  }

  setUp(() {
    book = const EpubParser().parseBytes(buildEpubFixture()).book;
    backend = makeBackend();
  });

  test('paginates and navigates within the EPUB', () async {
    expect(backend.format.name, 'epub');
    expect(backend.pageCount, greaterThan(1));
    expect(backend.currentLocator, isNotNull);
    expect(backend.positionLabel, contains('Page 1'));

    expect(await backend.next(), isTrue);
    expect(backend.pageIndex, 1);
    expect(await backend.previous(), isTrue);
    expect(backend.pageIndex, 0);
    expect(await backend.previous(), isFalse);
  });

  test('restores the page containing a locator across a typography change', () {
    final int target = book.globalOffset(1, 20);
    final EpubLocator targetLocator = book.locatorAt(target);
    expect(backend.goToLocator(targetLocator.toString()), isTrue);
    final int oldPage = backend.pageIndex;
    expect(backend.currentPage.start, lessThanOrEqualTo(target));
    expect(backend.currentPage.end, greaterThan(target));

    final EpubReaderBackend narrower = makeBackend(width: 220, height: 300);
    expect(narrower.goToLocator(targetLocator.toString()), isTrue);
    final EpubLocator restored = EpubLocator.tryParse(narrower.currentLocator)!;
    expect(restored.spineIndex, targetLocator.spineIndex);
    expect(narrower.currentPage.start, lessThanOrEqualTo(target));
    expect(narrower.currentPage.end, greaterThan(target));
    expect(narrower.chapterTitleForLocator(restored.toString()), 'Chapter Two');
    expect(oldPage, greaterThanOrEqualTo(0));
  });

  test('searches and maps fractions without losing the locator', () {
    final List<EpubSearchResult> results = backend.search('repeated phrase');
    expect(results, hasLength(2));
    expect(backend.goToOffset(results.last.globalOffset), isTrue);
    expect(backend.chapterTitleForPage(backend.pageIndex), 'Chapter Two');

    final String locator = backend.currentLocator!;
    final double fraction = backend.textFraction;
    final int offset = backend.offsetForFraction(fraction);
    expect(offset, greaterThanOrEqualTo(0));
    expect(backend.fractionForLocator(locator), closeTo(fraction, 0.001));
  });

  test('creates stable annotation ranges and page spans', () {
    final int start = book.text.indexOf('Alpha');
    final int end = start + 'Alpha bravo'.length;
    final EpubSelection selection = backend.selectionFor(start, end)!;

    expect(selection.chapterIndex, 0);
    expect(selection.chapterTitle, 'Chapter One');
    expect(selection.excerpt, contains('Alpha'));
    expect(selection.startLocator, startsWith('epub:spine=0;char='));
    expect(selection.endLocator, startsWith('epub:spine=0;char='));

    final Annotation annotation = Annotation(
      id: 'annotation-1',
      documentId: 'document-1',
      kind: AnnotationKind.note,
      startLocator: selection.startLocator,
      endLocator: selection.endLocator,
      chapterIndex: selection.chapterIndex,
      chapterTitle: selection.chapterTitle,
      excerpt: selection.excerpt,
      note: 'A note',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final ({int start, int end}) range = backend.annotationRange(annotation)!;
    expect(range.start, start);
    expect(range.end, end);
    expect(backend.canResolveAnnotation(annotation), isTrue);

    final EpubAnnotationSpan span = backend.annotationSpans(<Annotation>[
      annotation,
    ]).single;
    expect(span.kind, 'note');
    expect(span.hasNote, isTrue);
    expect(span.start, start);
    expect(span.end, end);

    expect(backend.goToOffset(start), isTrue);
    final List<EpubAnnotationSpan> pageSpans = backend.spansForPage(
      backend.pageIndex,
      <Annotation>[annotation],
    );
    final TextPage page = backend.currentPage;
    final EpubAnnotationSpan pageSpan = pageSpans.single;
    expect(pageSpan.annotationId, 'annotation-1');
    expect(pageSpan.start, greaterThanOrEqualTo(page.start));
    expect(pageSpan.end, lessThanOrEqualTo(page.end));
  });

  test(
    'keeps an orphaned annotation unresolved instead of silently moving it',
    () {
      final Annotation orphan = Annotation(
        id: 'orphan',
        documentId: 'document-1',
        kind: AnnotationKind.highlight,
        startLocator: 'epub:spine=99;char=3',
        endLocator: 'epub:spine=99;char=9',
        excerpt: 'missing',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        orphaned: true,
      );
      expect(backend.annotationRange(orphan), isNull);
      expect(backend.canResolveAnnotation(orphan), isFalse);
      expect(backend.annotationSpans(<Annotation>[orphan]), isEmpty);
    },
  );

  test('dispose releases the paginator without touching the book', () async {
    await backend.dispose();
    expect(book.text, isNotEmpty);
  });
}
