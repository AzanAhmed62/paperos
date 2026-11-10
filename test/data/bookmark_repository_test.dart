import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/library/data/bookmark_repository.dart';
import 'package:paperos/features/library/data/document_repository.dart';
import 'package:paperos/features/library/domain/document.dart';

import 'support.dart';

void main() {
  initFfi();

  late AppDatabaseOpener opener;
  late DocumentRepository documents;
  late BookmarkRepository bookmarks;

  setUp(() async {
    resetIds();
    opener = openTestDatabase();
    documents = DocumentRepository(opener);
    bookmarks = BookmarkRepository(opener);
    // The bookmarks table has a foreign key to documents, so the parent must
    // exist before a bookmark can point at it.
    await documents.insert(makeDocument(id: 'doc', pageCount: 100));
  });

  tearDown(() async {
    await bookmarks.dispose();
    await documents.dispose();
    await (await opener.database).close();
  });

  group('add', () {
    test('stores a bookmark at a page and reads it back', () async {
      final Bookmark added = await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atPage(7),
        label: 'Chapter two',
      );

      expect(added.documentId, 'doc');
      expect(added.page, 7);
      expect(added.label, 'Chapter two');

      final List<Bookmark> stored = await bookmarks.listFor('doc');
      expect(stored, hasLength(1));
      expect(stored.single.position, const ReadingPosition.atPage(7));
    });

    test('is idempotent at the same position', () async {
      final Bookmark first = await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atPage(4),
      );
      final Bookmark second = await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atPage(4),
      );

      expect(second.id, first.id);
      expect(await bookmarks.countFor('doc'), 1);
    });

    test('updates the label when the position already exists', () async {
      await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atPage(4),
        label: 'Old',
      );
      final Bookmark again = await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atPage(4),
        label: 'New',
      );

      expect(again.label, 'New');
      expect((await bookmarks.listFor('doc')).single.label, 'New');
    });

    test('keeps distinct positions separate', () async {
      await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atPage(1),
      );
      await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atPage(2),
      );

      expect(await bookmarks.countFor('doc'), 2);
    });

    test('a fraction-only bookmark round-trips as a fraction', () async {
      await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atFraction(0.42),
      );

      final Bookmark stored = (await bookmarks.listFor('doc')).single;
      expect(stored.page, -1);
      expect(stored.fraction, closeTo(0.42, 0.0001));
      expect(stored.position.page, isNull);
      expect(stored.position.fraction, closeTo(0.42, 0.0001));
    });
  });

  group('query', () {
    test('atPosition finds an exact match and nothing else', () async {
      await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atPage(9),
      );

      expect(
        await bookmarks.atPosition(
          documentId: 'doc',
          position: const ReadingPosition.atPage(9),
        ),
        isNotNull,
      );
      expect(
        await bookmarks.atPosition(
          documentId: 'doc',
          position: const ReadingPosition.atPage(10),
        ),
        isNull,
      );
    });

    test('countsByDocument groups across documents in one query', () async {
      await documents.insert(makeDocument(id: 'other', pageCount: 10));
      await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atPage(1),
      );
      await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atPage(2),
      );
      await bookmarks.add(
        documentId: 'other',
        position: const ReadingPosition.atPage(1),
      );

      final Map<String, int> counts = await bookmarks.countsByDocument();
      expect(counts, <String, int>{'doc': 2, 'other': 1});
      expect(await bookmarks.countAll(), 3);
    });

    test('orders bookmarks by page', () async {
      for (final int page in <int>[30, 5, 18]) {
        await bookmarks.add(
          documentId: 'doc',
          position: ReadingPosition.atPage(page),
        );
      }

      final List<int> pages = (await bookmarks.listFor('doc'))
          .map((Bookmark b) => b.page)
          .toList();
      expect(pages, <int>[5, 18, 30]);
    });
  });

  group('remove', () {
    test('removes a single bookmark by id', () async {
      final Bookmark bookmark = await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atPage(3),
      );

      await bookmarks.remove(bookmark.id);
      expect(await bookmarks.countFor('doc'), 0);
    });

    test('removeAllFor clears only the target document', () async {
      await documents.insert(makeDocument(id: 'other'));
      await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atPage(1),
      );
      await bookmarks.add(
        documentId: 'other',
        position: const ReadingPosition.atPage(1),
      );

      await bookmarks.removeAllFor('doc');

      expect(await bookmarks.countFor('doc'), 0);
      expect(await bookmarks.countFor('other'), 1);
    });

    test('deleting a document cascades to its bookmarks', () async {
      await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition.atPage(1),
      );

      await documents.delete('doc');

      expect(await bookmarks.countFor('doc'), 0);
      expect(await bookmarks.countsByDocument(), isEmpty);
    });
  });
}
