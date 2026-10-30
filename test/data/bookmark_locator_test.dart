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
    await documents.insert(
      makeDocument(id: 'doc', format: DocumentFormat.epub),
    );
  });

  tearDown(() async {
    await bookmarks.dispose();
    await documents.dispose();
    await (await opener.database).close();
  });

  test('persists the EPUB locator and chapter title', () async {
    final Bookmark added = await bookmarks.add(
      documentId: 'doc',
      position: const ReadingPosition(
        page: 4,
        fraction: 0.25,
        locator: 'epub:spine=1;char=40',
      ),
      chapterTitle: 'Chapter Two',
      excerpt: 'A passage',
    );

    final Bookmark stored = (await bookmarks.listFor('doc')).single;
    expect(stored.locator, 'epub:spine=1;char=40');
    expect(stored.chapterTitle, 'Chapter Two');
    expect(stored.displayLabel, 'Chapter Two');
    expect(stored.position.locator, 'epub:spine=1;char=40');
    expect(added.id, stored.id);
  });

  test(
    'finds an existing bookmark by locator even if the page changed',
    () async {
      final Bookmark first = await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition(
          page: 4,
          fraction: 0.25,
          locator: 'epub:spine=1;char=40',
        ),
      );
      final Bookmark second = await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition(
          page: 9,
          fraction: 0.55,
          locator: 'epub:spine=1;char=40',
        ),
      );
      expect(second.id, first.id);
      expect(await bookmarks.countFor('doc'), 1);
    },
  );

  test(
    'updates chapter metadata when the same locator is bookmarked again',
    () async {
      await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition(
          page: 2,
          fraction: 0.1,
          locator: 'epub:spine=0;char=8',
        ),
        label: 'Old label',
        chapterTitle: 'Old chapter',
      );
      final Bookmark updated = await bookmarks.add(
        documentId: 'doc',
        position: const ReadingPosition(
          page: 2,
          fraction: 0.1,
          locator: 'epub:spine=0;char=8',
        ),
        label: 'New label',
        chapterTitle: 'New chapter',
      );
      expect(updated.label, 'New label');
      expect(updated.chapterTitle, 'New chapter');
      final Bookmark stored = (await bookmarks.listFor('doc')).single;
      expect(stored.label, 'New label');
      expect(stored.chapterTitle, 'New chapter');
    },
  );

  test('pointsAt prefers the stable locator over page drift', () {
    final Bookmark bookmark = Bookmark(
      id: 'b',
      documentId: 'doc',
      page: 4,
      fraction: 0.2,
      locator: 'epub:spine=1;char=40',
      createdAt: DateTime(2026, 1, 1),
    );
    expect(
      bookmark.pointsAt(
        const ReadingPosition(page: 99, locator: 'epub:spine=1;char=40'),
      ),
      isTrue,
    );
    expect(
      bookmark.pointsAt(
        const ReadingPosition(page: 99, locator: 'epub:spine=1;char=41'),
      ),
      isFalse,
    );
  });
}
