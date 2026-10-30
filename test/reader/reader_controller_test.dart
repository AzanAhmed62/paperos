import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/errors/paper_exception.dart';
import 'package:paperos/core/platform/pdf_service.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/core/storage/app_storage.dart';
import 'package:paperos/features/annotations/data/annotation_repository.dart';
import 'package:paperos/features/annotations/domain/annotation.dart';
import 'package:paperos/features/library/data/bookmark_repository.dart';
import 'package:paperos/features/library/data/document_repository.dart';
import 'package:paperos/features/library/domain/document.dart';
import 'package:paperos/features/reader/application/reader_controller.dart';
import 'package:paperos/features/reader/domain/reader_backend.dart';
import 'package:paperos/features/reader/epub/epub_reader_backend.dart';
import 'package:paperos/features/settings/application/settings_controller.dart';
import 'package:paperos/features/settings/domain/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/support.dart';
import '../support/epub_fixture.dart';

class _NoPdfService implements PdfService {
  @override
  bool get isSupported => false;

  @override
  Future<void> close(String handle) async {}

  @override
  Future<PdfDocumentHandle> open(String path) async =>
      throw const PaperException.unsupportedFormat('No PDFs in this test.');

  @override
  Future<PdfPageImage> renderPage(
    String handle,
    int pageIndex, {
    int widthPx = 1080,
  }) async =>
      throw const PaperException.unsupportedFormat('No PDFs in this test.');
}

void main() {
  initFfi();

  late Directory temp;
  late AppDatabaseOpener opener;
  late DocumentRepository documents;
  late AnnotationRepository annotations;
  late BookmarkRepository bookmarks;
  late ProviderContainer container;
  late File epubFile;
  late Document document;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    temp = await Directory.systemTemp.createTemp('paperos_reader_');
    epubFile = File('${temp.path}/book.epub');
    await epubFile.writeAsBytes(buildEpubFixture(), flush: true);
    opener = openTestDatabase();
    documents = DocumentRepository(opener);
    annotations = AnnotationRepository(opener);
    bookmarks = BookmarkRepository(opener);
    document = makeDocument(
      id: 'book',
      title: 'A Test Book',
      format: DocumentFormat.epub,
      pageCount: 1,
      localPath: epubFile.path,
    );
    await documents.insert(document);

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appDatabaseProvider.overrideWithValue(opener),
        appStorageProvider.overrideWithValue(
          AppStorage(rootOverride: () async => temp),
        ),
        pdfServiceProvider.overrideWithValue(_NoPdfService()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await annotations.dispose();
    await bookmarks.dispose();
    await documents.dispose();
    await (await opener.database).close();
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test(
    'opens EPUB, navigates and persists an annotation and bookmark',
    () async {
      final provider = readerProvider(document.id);
      final ProviderSubscription<AsyncValue<ReaderState>> subscription =
          container.listen(provider, (_, _) {});
      final ReaderState initial = await container.read(provider.future);
      final ReaderSession session = container.read(provider.notifier);

      expect(initial.backend.format, ReaderFormat.epub);
      expect(initial.document.title, 'A Test Book');
      expect(session.toc, hasLength(2));
      expect(session.toc.first.children, isNotEmpty);

      session.setViewport(const Size(420, 600));
      await Future<void>.delayed(Duration.zero);
      final ReaderState paged = container.read(provider).requireValue;
      expect(paged.pageCount, greaterThan(1));

      final EpubReaderBackend backend = session.epubBackend!;
      final int start = backend.book.text.indexOf('Alpha');
      final int end = start + 'Alpha bravo'.length;
      final Annotation annotation = (await session.addAnnotation(
        kind: AnnotationKind.highlight,
        start: start,
        end: end,
      ))!;
      expect(annotation.excerpt, contains('Alpha'));
      expect(annotation.startLocator, startsWith('epub:spine=0;char='));
      expect(container.read(provider).requireValue.annotations, hasLength(1));

      await session.updateAnnotationNote(annotation.id, 'A thought');
      expect(
        container.read(provider).requireValue.annotations.single.note,
        'A thought',
      );
      expect(await annotations.countAll(), 1);

      await session.toggleBookmark();
      expect(container.read(provider).requireValue.bookmarks, hasLength(1));
      final Bookmark bookmark = (await bookmarks.listFor(document.id)).single;
      expect(bookmark.chapterTitle, 'Chapter One');
      expect(bookmark.locator, isNotNull);

      await session.goToTocEntry(session.toc.last);
      expect(container.read(provider).requireValue.position.locator, isNotNull);

      subscription.close();
    },
  );

  test(
    'switches between paged and scroll flow without losing the place',
    () async {
      final provider = readerProvider(document.id);
      final ProviderSubscription<AsyncValue<ReaderState>> subscription =
          container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final ReaderSession session = container.read(provider.notifier);
      session.setViewport(const Size(420, 600));
      await Future<void>.delayed(Duration.zero);

      final int start =
          (session.epubBackend?.book.text.indexOf('Foxtrot') ?? 0);
      await session.goToOffset(start);
      final String pagedLocator = container
          .read(provider)
          .requireValue
          .position
          .locator!;

      await container
          .read(settingsProvider.notifier)
          .setReaderFlow(ReaderFlow.scroll);
      session.applyReaderSettings();
      final ReaderState scrolled = container.read(provider).requireValue;
      expect(scrolled.scrollPosition, isNotNull);
      expect(scrolled.scrollPosition!.locator, pagedLocator);

      session.setScrollFraction(0.8);
      final ReaderState moved = container.read(provider).requireValue;
      expect(moved.progress, closeTo(0.8, 0.01));
      expect(moved.scrollPosition!.locator, isNotNull);

      await container
          .read(settingsProvider.notifier)
          .setReaderFlow(ReaderFlow.paged);
      session.applyReaderSettings();
      final ReaderState paged = container.read(provider).requireValue;
      expect(paged.scrollPosition, isNull);
      expect(paged.position.locator, isNotNull);

      subscription.close();
    },
  );

  test('reports a malformed EPUB as a recoverable document error', () async {
    final File broken = File('${temp.path}/broken.epub');
    await broken.writeAsString('not an epub', flush: true);
    final Document bad = makeDocument(
      id: 'broken',
      format: DocumentFormat.epub,
      localPath: broken.path,
    );
    await documents.insert(bad);

    final badProvider = readerProvider(bad.id);
    final ProviderSubscription<AsyncValue<ReaderState>> keepAlive = container
        .listen(badProvider, (_, _) {});
    await expectLater(
      container.read(badProvider.future),
      throwsA(
        isA<PaperException>().having(
          (PaperException error) => error.kind,
          'kind',
          PaperErrorKind.corruptDocument,
        ),
      ),
    );
    keepAlive.close();
  });
}
