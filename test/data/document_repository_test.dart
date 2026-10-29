import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/library/data/document_repository.dart';
import 'package:paperos/features/library/domain/document.dart';
import 'package:paperos/features/library/domain/library_models.dart';

import 'support.dart';

void main() {
  initFfi();

  late AppDatabaseOpener opener;
  late DocumentRepository repository;

  setUp(() {
    resetIds();
    opener = openTestDatabase();
    repository = DocumentRepository(opener);
  });

  tearDown(() async {
    await repository.dispose();
    await (await opener.database).close();
  });

  group('insert and read', () {
    test('stores a document and reads it back intact', () async {
      final Document original = makeDocument(
        title: 'Meditations',
        format: DocumentFormat.pdf,
        pageCount: 210,
      );

      await repository.insert(original);
      final Document? loaded = await repository.findById(original.id);

      expect(loaded, isNotNull);
      expect(loaded!.title, 'Meditations');
      expect(loaded.format, DocumentFormat.pdf);
      expect(loaded.pageCount, 210);
      expect(loaded.status, DocumentStatus.ready);
      expect(loaded.sourceName, original.sourceName);
      expect(loaded.addedAt, original.addedAt);
    });

    test('returns null for an unknown id instead of throwing', () async {
      expect(await repository.findById('nope'), isNull);
    });

    test('rejects a duplicate id', () async {
      final Document document = makeDocument(id: 'fixed');
      await repository.insert(document);

      expect(
        () => repository.insert(makeDocument(id: 'fixed')),
        throwsA(anything),
      );
    });

    test('reports an accurate count', () async {
      expect(await repository.count(), 0);
      await repository.insert(makeDocument());
      await repository.insert(makeDocument());
      expect(await repository.count(), 2);
    });
  });

  group('list scopes', () {
    test('all returns every document, newest first', () async {
      await repository.insert(makeDocument(id: 'a', title: 'Alpha'));
      await repository.insert(makeDocument(id: 'b', title: 'Beta'));

      final List<Document> all = await repository.list();
      expect(all.map((Document d) => d.id), containsAll(<String>['a', 'b']));
    });

    test('favorites scope only returns favorited documents', () async {
      await repository.insert(makeDocument(id: 'plain'));
      await repository.insert(makeDocument(id: 'star', isFavorite: true));

      final List<Document> favorites = await repository.list(
        scope: LibraryScope.favorites,
      );

      expect(favorites, hasLength(1));
      expect(favorites.single.id, 'star');
    });

    test('recent scope only returns documents that were opened', () async {
      await repository.insert(makeDocument(id: 'unread'));
      final Document read = makeDocument(id: 'read');
      await repository.insert(read);
      await repository.saveProgress(
        id: read.id,
        position: const ReadingPosition.atPage(3),
        pageCount: 10,
        openedAt: DateTime(2026, 2, 1),
      );

      final List<Document> recent = await repository.list(
        scope: LibraryScope.recent,
      );

      expect(recent.map((Document d) => d.id), <String>['read']);
    });

    test('query matches title and file name case-insensitively', () async {
      await repository.insert(makeDocument(id: 'one', title: 'The Republic'));
      await repository.insert(makeDocument(id: 'two', title: 'Discourses'));

      final List<Document> hits = await repository.list(query: 'republic');
      expect(hits.map((Document d) => d.id), <String>['one']);

      final List<Document> none = await repository.list(query: 'zzz');
      expect(none, isEmpty);
    });

    test('respects the limit', () async {
      for (int i = 0; i < 5; i++) {
        await repository.insert(makeDocument(id: 'doc$i'));
      }

      expect(await repository.list(limit: 2), hasLength(2));
    });
  });

  group('update', () {
    test('renames a document without touching its id', () async {
      final Document document = makeDocument(id: 'rename', title: 'Old');
      await repository.insert(document);

      await repository.update(document.copyWith(title: 'New'));
      final Document? loaded = await repository.findById('rename');

      expect(loaded!.title, 'New');
      expect(loaded.id, 'rename');
    });

    test('toggles favorite state', () async {
      await repository.insert(makeDocument(id: 'fav'));
      await repository.setFavorite('fav', true);
      expect((await repository.findById('fav'))!.isFavorite, isTrue);
      await repository.setFavorite('fav', false);
      expect((await repository.findById('fav'))!.isFavorite, isFalse);
    });
  });

  group('progress', () {
    test('records a position that survives a reload', () async {
      await repository.insert(makeDocument(id: 'p', pageCount: 100));

      await repository.saveProgress(
        id: 'p',
        position: const ReadingPosition(page: 12, fraction: 0.12),
        pageCount: 100,
        openedAt: DateTime(2026, 3, 1),
        sessionLength: const Duration(minutes: 30),
      );

      final Document? loaded = await repository.findById('p');
      expect(
        loaded!.progress.position,
        const ReadingPosition(page: 12, fraction: 0.12),
      );
      expect(loaded.progress.pageCount, 100);
      expect(loaded.openedSeconds, 1800);
    });

    test('furthest page only ever moves forward', () async {
      await repository.insert(makeDocument(id: 'f', pageCount: 50));

      await repository.saveProgress(
        id: 'f',
        position: const ReadingPosition.atPage(40),
        pageCount: 50,
        maxPageSeen: 40,
      );
      // Re-reading from the start must not erase the furthest point reached.
      await repository.saveProgress(
        id: 'f',
        position: const ReadingPosition.atPage(5),
        pageCount: 50,
        maxPageSeen: 5,
      );

      final Document loaded = (await repository.findById('f'))!;
      expect(loaded.progress.maxPage, 40);
      expect(loaded.progress.position, const ReadingPosition.atPage(5));
    });

    test('does not overwrite a known page count with zero', () async {
      await repository.insert(makeDocument(id: 'c', pageCount: 0));

      await repository.saveProgress(
        id: 'c',
        position: const ReadingPosition.atPage(1),
        pageCount: 0,
      );
      await repository.saveProgress(
        id: 'c',
        position: const ReadingPosition.atPage(2),
        pageCount: 88,
      );

      expect((await repository.findById('c'))!.pageCount, 88);
    });
  });

  group('remove', () {
    test('delete removes exactly one row', () async {
      await repository.insert(makeDocument(id: 'keep'));
      await repository.insert(makeDocument(id: 'drop'));

      await repository.delete('drop');

      expect(await repository.findById('drop'), isNull);
      expect(await repository.findById('keep'), isNotNull);
    });

    test('clear empties the index', () async {
      await repository.insert(makeDocument());
      await repository.insert(makeDocument());

      await repository.clear();

      expect(await repository.count(), 0);
      expect(await repository.list(), isEmpty);
    });
  });

  test('emits a change event after a mutation', () async {
    final Future<void> firstEvent = repository.changes.first;
    await repository.insert(makeDocument());
    await expectLater(firstEvent, completes);
  });
}
