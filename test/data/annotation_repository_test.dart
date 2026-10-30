import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/annotations/data/annotation_repository.dart';
import 'package:paperos/features/annotations/domain/annotation.dart';
import 'package:paperos/features/library/data/document_repository.dart';
import 'package:paperos/features/library/domain/document.dart';

import 'support.dart';

void main() {
  initFfi();

  late AppDatabaseOpener opener;
  late DocumentRepository documents;
  late AnnotationRepository annotations;

  setUp(() async {
    resetIds();
    opener = openTestDatabase();
    documents = DocumentRepository(opener);
    annotations = AnnotationRepository(opener);
    await documents.insert(
      makeDocument(id: 'doc', format: DocumentFormat.epub),
    );
    await documents.insert(
      makeDocument(id: 'other', format: DocumentFormat.epub),
    );
  });

  tearDown(() async {
    await annotations.dispose();
    await documents.dispose();
    await (await opener.database).close();
  });

  Future<Annotation> add({
    String documentId = 'doc',
    AnnotationKind kind = AnnotationKind.highlight,
    int chapter = 1,
    String? note,
  }) {
    return annotations.add(
      documentId: documentId,
      kind: kind,
      startLocator: 'epub:spine=$chapter;char=10',
      endLocator: 'epub:spine=$chapter;char=20',
      chapterIndex: chapter,
      chapterTitle: 'Chapter $chapter',
      excerpt: 'The selected passage',
      note: note,
    );
  }

  test('adds, reads and orders annotations per document', () async {
    final Annotation later = await add(chapter: 3);
    final Annotation earlier = await add(chapter: 1, kind: AnnotationKind.note);
    await add(documentId: 'other', chapter: 2);

    final List<Annotation> stored = await annotations.listFor('doc');
    expect(stored, hasLength(2));
    expect(stored.map((Annotation a) => a.id), <String>[earlier.id, later.id]);
    expect(stored.last.chapterTitle, 'Chapter 3');
    expect(stored.first.kind, AnnotationKind.note);
    expect(await annotations.countAll(), 3);
    expect(await annotations.countsByDocument(), <String, int>{
      'doc': 2,
      'other': 1,
    });
  });

  test('updates and clears a note while preserving the anchor', () async {
    final Annotation original = await add();
    await annotations.updateNote(original.id, '  A useful thought  ');
    Annotation stored = (await annotations.listFor('doc')).single;
    expect(stored.note, 'A useful thought');
    expect(stored.hasNote, isTrue);
    expect(stored.startLocator, original.startLocator);
    expect(
      stored.updatedAt.isAfter(original.updatedAt) ||
          stored.updatedAt == original.updatedAt,
      isTrue,
    );

    await annotations.updateNote(original.id, '   ');
    stored = (await annotations.listFor('doc')).single;
    expect(stored.note, isNull);
    expect(stored.hasNote, isFalse);
  });

  test('marks an unresolved anchor as orphaned and can recover it', () async {
    final Annotation original = await add();
    await annotations.markOrphaned(original.id);
    Annotation stored = (await annotations.listFor('doc')).single;
    expect(stored.orphaned, isTrue);
    expect(stored.excerpt, original.excerpt);
    expect(stored.note, original.note);

    await annotations.markOrphaned(original.id, orphaned: false);
    stored = (await annotations.listFor('doc')).single;
    expect(stored.orphaned, isFalse);
  });

  test('removes a single annotation', () async {
    final Annotation first = await add(chapter: 1);
    await add(chapter: 2);
    await annotations.remove(first.id);
    final List<Annotation> stored = await annotations.listFor('doc');
    expect(stored, hasLength(1));
    expect(stored.single.chapterIndex, 2);
  });

  test('deleting a document cascades to its annotations only', () async {
    await add();
    await add(documentId: 'other');
    await documents.delete('doc');

    expect(await annotations.listFor('doc'), isEmpty);
    expect(await annotations.listFor('other'), hasLength(1));
    expect(await annotations.countAll(), 1);
  });

  test('emits a change event after a mutation', () async {
    final Future<void> changed = annotations.changes.first;
    await add();
    await changed.timeout(const Duration(seconds: 2));
  });
}
