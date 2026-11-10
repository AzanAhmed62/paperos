import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/library/data/document_repository.dart';
import 'package:paperos/features/library/domain/document.dart';
import 'package:paperos/features/library/domain/library_models.dart';

import 'support.dart';

void main() {
  initFfi();

  late AppDatabaseOpener opener;
  late DocumentRepository documents;

  setUp(() {
    resetIds();
    opener = openTestDatabase();
    documents = DocumentRepository(opener);
  });

  tearDown(() async {
    await documents.dispose();
    await (await opener.database).close();
  });

  test(
    'filters EPUB, unread, in-progress and completed without guessing',
    () async {
      final Document unreadEpub = makeDocument(
        id: 'unread-epub',
        title: 'Unread EPUB',
        format: DocumentFormat.epub,
        pageCount: 100,
      );
      final Document progressEpub =
          makeDocument(
            id: 'progress-epub',
            title: 'Progress EPUB',
            format: DocumentFormat.epub,
            pageCount: 100,
          ).copyWith(
            progress: const ReadingProgress(
              position: ReadingPosition(
                page: 4,
                fraction: 0.25,
                locator: 'epub:spine=0;char=2',
              ),
              maxPage: 4,
              pageCount: 100,
            ),
            lastOpenedAt: DateTime(2026, 1, 3),
            author: 'Zed Author',
          );
      final Document finishedEpub =
          makeDocument(
            id: 'finished-epub',
            title: 'Finished EPUB',
            format: DocumentFormat.epub,
            pageCount: 100,
          ).copyWith(
            progress: const ReadingProgress(
              position: ReadingPosition.atFraction(0.999),
              maxPage: 100,
              pageCount: 100,
            ),
            lastOpenedAt: DateTime(2026, 1, 2),
            author: 'Ada Author',
          );
      final Document pdf = makeDocument(
        id: 'pdf',
        title: 'A PDF',
        format: DocumentFormat.pdf,
        pageCount: 10,
      );

      for (final Document document in <Document>[
        unreadEpub,
        progressEpub,
        finishedEpub,
        pdf,
      ]) {
        await documents.insert(document);
      }

      expect(
        (await documents.list(scope: LibraryScope.epub))
            .map((Document d) => d.id),
        containsAll(<String>['unread-epub', 'progress-epub', 'finished-epub']),
      );
      expect((await documents.list(scope: LibraryScope.pdf)).single.id, 'pdf');
      expect(
        (await documents.list(scope: LibraryScope.unread))
            .map((Document d) => d.id),
        containsAll(<String>['unread-epub', 'pdf']),
      );
      expect(
        (await documents.list(scope: LibraryScope.inProgress)).single.id,
        'progress-epub',
      );
      expect(
        (await documents.list(scope: LibraryScope.completed)).single.id,
        'finished-epub',
      );
    },
  );

  test(
    'sorts by title and author without putting unknown authors first',
    () async {
      await documents.insert(
        makeDocument(id: 'b', title: 'Beta').copyWith(author: 'Zed'),
      );
      await documents.insert(
        makeDocument(id: 'a', title: 'Alpha').copyWith(author: 'Ada'),
      );
      await documents.insert(makeDocument(id: 'c', title: 'Charlie'));

      final List<Document> byTitle = await documents.list(
        sort: LibrarySort.title,
      );
      expect(byTitle.map((Document d) => d.id), <String>['a', 'b', 'c']);

      final List<Document> byAuthor = await documents.list(
        sort: LibrarySort.author,
      );
      expect(byAuthor.map((Document d) => d.id).take(2), <String>['a', 'b']);
      expect(byAuthor.last.id, 'c');
    },
  );

  test('searches the author as well as the title and source name', () async {
    await documents.insert(
      makeDocument(
        id: 'book',
        title: 'A Book',
      ).copyWith(author: 'Ursula Author'),
    );
    expect((await documents.list(query: 'ursula')).single.id, 'book');
    expect((await documents.list(query: 'a book')).single.id, 'book');
  });

  test('relink keeps a custom title and user progress', () async {
    final Document original =
        makeDocument(
          id: 'book',
          title: 'My name',
          format: DocumentFormat.epub,
        ).copyWith(
          sourceName: 'original.epub',
          progress: const ReadingProgress(
            position: ReadingPosition.atFraction(0.4),
            maxPage: 3,
            pageCount: 10,
          ),
        );
    await documents.insert(original);
    final Document relinked = await documents.relink(
      original,
      localPath: '/library/book.epub',
      sourceUri: 'content://book',
      sourceName: 'book.epub',
      byteSize: 2048,
      pageCount: 12,
      status: DocumentStatus.ready,
      fingerprint: 'abc',
      title: 'Metadata title',
    );
    expect(relinked.id, original.id);
    expect(relinked.title, 'My name');
    expect(relinked.progress.position?.fraction, 0.4);
    expect(relinked.fingerprint, 'abc');
  });
}
