import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/features/annotations/data/annotation_export_service.dart';
import 'package:paperos/features/annotations/domain/annotation.dart';
import 'package:paperos/features/library/domain/document.dart';

import '../data/support.dart';

void main() {
  final DateTime created = DateTime(2026, 3, 1, 10, 30);
  final Document document = makeDocument(
    id: 'book-1',
    title: 'The Paper Road',
    format: DocumentFormat.epub,
  ).copyWith(author: 'Ada Lovelace');

  Annotation annotation({
    required String id,
    required int? chapter,
    required String chapterTitle,
    required String excerpt,
    String? note,
    bool orphaned = false,
    AnnotationKind kind = AnnotationKind.highlight,
    DateTime? at,
  }) {
    return Annotation(
      id: id,
      documentId: 'book-1',
      kind: kind,
      startLocator: 'epub:spine=${chapter ?? 0};char=4',
      endLocator: 'epub:spine=${chapter ?? 0};char=20',
      excerpt: excerpt,
      chapterIndex: chapter,
      chapterTitle: chapterTitle,
      note: note,
      orphaned: orphaned,
      createdAt: at ?? created,
      updatedAt: at ?? created,
    );
  }

  Bookmark bookmark({
    required String id,
    required String label,
    String? excerpt,
    String? chapter,
  }) {
    return Bookmark(
      id: id,
      documentId: 'book-1',
      page: 3,
      fraction: 0.25,
      label: label,
      excerpt: excerpt,
      locator: 'epub:spine=1;char=8',
      chapterTitle: chapter ?? 'Chapter One',
      createdAt: created,
    );
  }

  test('Markdown groups chapters, quotes excerpts and discloses orphans', () {
    final AnnotationExport export = AnnotationExportBuilder.build(
      document: document,
      exportedAt: created,
      bookmarks: <Bookmark>[
        bookmark(id: 'mark-1', label: 'A bookmark', excerpt: 'A saved line'),
      ],
      annotations: <Annotation>[
        annotation(
          id: 'a-2',
          chapter: 1,
          chapterTitle: 'Second Chapter',
          excerpt: 'Second excerpt',
          kind: AnnotationKind.underline,
          at: created.add(const Duration(minutes: 1)),
        ),
        annotation(
          id: 'a-1',
          chapter: 0,
          chapterTitle: 'First Chapter',
          excerpt: 'First excerpt',
          note: 'Remember this',
        ),
        annotation(
          id: 'a-3',
          chapter: 8,
          chapterTitle: 'Old Chapter',
          excerpt: 'Detached excerpt',
          note: 'Detached note',
          orphaned: true,
        ),
      ],
    );

    final String markdown = export.markdown;
    expect(markdown, contains('# The Paper Road'));
    expect(markdown, contains('*by Ada Lovelace*'));
    expect(markdown, contains('## Bookmarks'));
    expect(markdown, contains('### A bookmark'));
    expect(markdown, contains('> A saved line'));
    expect(markdown, contains('## Annotations'));
    expect(markdown, contains('### First Chapter'));
    expect(markdown, contains('### Second Chapter'));
    expect(
      markdown.indexOf('### First Chapter'),
      lessThan(markdown.indexOf('### Second Chapter')),
    );
    expect(markdown, contains('**Note:** Remember this'));
    expect(markdown, contains('**Orphaned annotations: 1 of 3.**'));
    expect(markdown, contains('**Orphaned:** this annotation could not'));
    expect(markdown, contains('> Detached excerpt'));
    expect(markdown, contains('**Note:** Detached note'));
    expect(markdown, contains('epub:spine=0;char=4'));
    expect(export.fileStem, 'The Paper Road annotations');
  });

  test(
    'JSON carries explicit book, chapters, counts and orphan disclosure',
    () {
      final AnnotationExport export = AnnotationExportBuilder.build(
        document: document,
        exportedAt: created,
        bookmarks: <Bookmark>[bookmark(id: 'mark-1', label: 'A bookmark')],
        annotations: <Annotation>[
          annotation(
            id: 'a-1',
            chapter: 0,
            chapterTitle: 'First Chapter',
            excerpt: 'First excerpt',
            note: 'A note',
          ),
          annotation(
            id: 'a-2',
            chapter: 8,
            chapterTitle: 'Old Chapter',
            excerpt: 'Detached',
            orphaned: true,
          ),
        ],
      );
      final Map<String, Object?> json =
          jsonDecode(export.json) as Map<String, Object?>;
      expect(json['format'], 'paperos.annotations');
      expect(json['version'], 1);
      expect(
        (json['book']! as Map<String, Object?>)['title'],
        'The Paper Road',
      );
      expect((json['book']! as Map<String, Object?>)['author'], 'Ada Lovelace');
      final Map<String, Object?> counts =
          json['counts']! as Map<String, Object?>;
      expect(counts['annotations'], 2);
      expect(counts['bookmarks'], 1);
      expect(counts['orphanedAnnotations'], 1);
      expect(json['orphanedDisclosure'], contains('preserved'));
      final List<Object?> annotations = json['annotations']! as List<Object?>;
      expect(annotations, hasLength(2));
      final Map<String, Object?> first =
          annotations.first as Map<String, Object?>;
      expect(first['id'], 'a-1');
      expect(first['type'], 'highlight');
      expect(first['chapterTitle'], 'First Chapter');
      expect(first['note'], 'A note');
      final Map<String, Object?> second =
          annotations.last as Map<String, Object?>;
      expect(second['orphaned'], isTrue);
      expect(second['orphanDisclosure'], contains('could not be anchored'));
      final List<Object?> bookmarks = json['bookmarks']! as List<Object?>;
      expect((bookmarks.single as Map<String, Object?>)['label'], 'A bookmark');
    },
  );

  test('preserves paragraph breaks in a multi-line personal note', () {
    final AnnotationExport export = AnnotationExportBuilder.build(
      document: document,
      exportedAt: created,
      bookmarks: const <Bookmark>[],
      annotations: <Annotation>[
        annotation(
          id: 'a-1',
          chapter: 0,
          chapterTitle: 'First Chapter',
          excerpt: 'A passage',
          note: 'First thought.\r\n\r\nSecond thought.\r\n',
        ),
      ],
    );

    expect(
      export.markdown,
      contains('**Note:**\n\nFirst thought.\n\nSecond thought.'),
    );
    expect(export.markdown, isNot(contains('First thought. Second thought.')));
  });

  test('uses a safe file stem and still exports an empty book', () {
    final Document unsafe = document.copyWith(title: 'A/B: C*?"<>|');
    final AnnotationExport export = AnnotationExportBuilder.build(
      document: unsafe,
      exportedAt: created,
      annotations: const <Annotation>[],
      bookmarks: const <Bookmark>[],
    );
    expect(export.fileStem, 'A B C annotations');
    expect(export.markdown, contains('0 annotations, 0 bookmarks.'));
    expect(export.markdown, isNot(contains('Orphaned annotations')));
    final Map<String, Object?> json =
        jsonDecode(export.json) as Map<String, Object?>;
    expect((json['counts']! as Map<String, Object?>)['annotations'], 0);
  });
}
