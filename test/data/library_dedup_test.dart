import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/errors/paper_exception.dart';
import 'package:paperos/core/platform/document_import_service.dart';
import 'package:paperos/core/platform/pdf_service.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/core/storage/app_storage.dart';
import 'package:paperos/features/annotations/data/annotation_repository.dart';
import 'package:paperos/features/annotations/domain/annotation.dart';
import 'package:paperos/features/library/data/bookmark_repository.dart';
import 'package:paperos/features/library/data/document_repository.dart';
import 'package:paperos/features/library/data/library_service.dart';
import 'package:paperos/features/library/domain/document.dart';
import 'package:path/path.dart' as p;

import 'support.dart';
import '../support/epub_fixture.dart';

class _NoPdfService implements PdfService {
  @override
  bool get isSupported => false;

  @override
  Future<void> close(String handle) async {}

  @override
  Future<PdfDocumentHandle> open(String path) async {
    throw const PaperException.unsupportedFormat('No PDFs in this test.');
  }

  @override
  Future<PdfPageImage> renderPage(
    String handle,
    int pageIndex, {
    int widthPx = 1080,
  }) async {
    throw const PaperException.unsupportedFormat('No PDFs in this test.');
  }
}

class _CountingPdfService implements PdfService {
  _CountingPdfService({this.failOnClose = false});

  final bool failOnClose;
  int closeCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<PdfDocumentHandle> open(String path) async => const PdfDocumentHandle(
    handle: 'probe-handle',
    pageCount: 7,
    pageWidthPt: 612,
    pageHeightPt: 792,
  );

  @override
  Future<void> close(String handle) async {
    closeCalls++;
    if (failOnClose) throw StateError('native close failed');
  }

  @override
  Future<PdfPageImage> renderPage(
    String handle,
    int pageIndex, {
    int widthPx = 1080,
  }) async {
    throw const PaperException.unsupportedFormat('Not needed for a probe.');
  }
}

void main() {
  initFfi();

  late Directory temp;
  late AppDatabaseOpener opener;
  late DocumentRepository documents;
  late BookmarkRepository bookmarks;
  late AnnotationRepository annotations;
  late LibraryService service;

  setUp(() async {
    resetIds();
    temp = await Directory.systemTemp.createTemp('paperos_dedup_');
    opener = openTestDatabase();
    documents = DocumentRepository(opener);
    bookmarks = BookmarkRepository(opener);
    annotations = AnnotationRepository(opener);
    service = LibraryService(
      documents: documents,
      bookmarks: bookmarks,
      storage: AppStorage(rootOverride: () async => temp),
      pdf: _NoPdfService(),
    );
  });

  tearDown(() async {
    await annotations.dispose();
    await bookmarks.dispose();
    await documents.dispose();
    await (await opener.database).close();
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<File> sourceFile(String name) async {
    final File file = File(p.join(temp.path, name));
    await file.writeAsBytes(buildEpubFixture(), flush: true);
    return file;
  }

  test('PDF probing closes the native handle exactly once', () async {
    final File source = File(p.join(temp.path, 'probe.pdf'));
    await source.writeAsBytes(const <int>[1, 2, 3], flush: true);
    final _CountingPdfService pdf = _CountingPdfService();
    final LibraryService probeService = LibraryService(
      documents: documents,
      bookmarks: bookmarks,
      storage: AppStorage(rootOverride: () async => temp),
      pdf: pdf,
    );

    final PdfProbe probe = await probeService.probePdf(source.path);

    expect(probe.pageCount, 7);
    expect(probe.failure, isNull);
    expect(pdf.closeCalls, 1);
  });

  test('a PDF close failure does not hide a readable page count', () async {
    final File source = File(p.join(temp.path, 'close-fails.pdf'));
    await source.writeAsBytes(const <int>[1, 2, 3], flush: true);
    final _CountingPdfService pdf = _CountingPdfService(failOnClose: true);
    final LibraryService probeService = LibraryService(
      documents: documents,
      bookmarks: bookmarks,
      storage: AppStorage(rootOverride: () async => temp),
      pdf: pdf,
    );

    final PdfProbe probe = await probeService.probePdf(source.path);

    expect(probe.pageCount, 7);
    expect(probe.failure, isNull);
    expect(pdf.closeCalls, 1);
  });

  test(
    'imports an EPUB, reads its metadata and writes a private cover',
    () async {
      final File source = await sourceFile('book.epub');
      final Document document = await service.importFile(
        PickedFile(
          path: source.path,
          name: 'book.epub',
          byteSize: await source.length(),
          sourceUri: 'content://provider/book',
        ),
      );

      expect(document.format, DocumentFormat.epub);
      expect(document.title, 'A Test Book');
      expect(document.author, 'Ada Lovelace');
      expect(document.publisher, 'Paper Press');
      expect(document.status, DocumentStatus.ready);
      expect(document.fingerprint, isNotNull);
      expect(File(document.localPath).existsSync(), isTrue);
      expect(document.localPath, isNot(source.path));
      expect(document.coverPath, isNotNull);
      expect(File(document.coverPath!).existsSync(), isTrue);
    },
  );

  test('re-importing the same source is a no-op, not a second row', () async {
    final File source = await sourceFile('same.epub');
    final PickedFile picked = PickedFile(
      path: source.path,
      name: 'same.epub',
      byteSize: await source.length(),
      sourceUri: 'content://provider/same',
    );
    final Document first = await service.importFile(picked);
    final Document second = await service.importFile(picked);

    expect(second.id, first.id);
    expect(await documents.count(), 1);
  });

  test(
    'revives a stale row and keeps progress, bookmarks and annotations',
    () async {
      final File source = await sourceFile('revive.epub');
      final PickedFile picked = PickedFile(
        path: source.path,
        name: 'revive.epub',
        byteSize: await source.length(),
        sourceUri: 'content://provider/revive',
      );
      final Document imported = await service.importFile(picked);
      await documents.saveProgress(
        id: imported.id,
        position: const ReadingPosition(
          page: 5,
          fraction: 0.25,
          locator: 'epub:spine=0;char=40',
        ),
        pageCount: 20,
        maxPageSeen: 5,
      );
      final Bookmark bookmark = await bookmarks.add(
        documentId: imported.id,
        position: const ReadingPosition(
          page: 5,
          fraction: 0.25,
          locator: 'epub:spine=0;char=40',
        ),
      );
      final Annotation annotation = await annotations.add(
        documentId: imported.id,
        kind: AnnotationKind.highlight,
        startLocator: 'epub:spine=0;char=10',
        endLocator: 'epub:spine=0;char=20',
        chapterIndex: 0,
        chapterTitle: 'Chapter One',
        excerpt: 'Alpha bravo',
      );
      final Document current = (await documents.findById(imported.id))!;
      await documents.update(current.copyWith(title: 'My renamed book'));

      // Simulate the app-private copy disappearing while the source is still
      // available. This is the duplicate-row bug the v1.1 import path fixes.
      await File(imported.localPath).delete();
      expect(File(imported.localPath).existsSync(), isFalse);

      final Document revived = await service.importFile(picked);
      expect(revived.id, imported.id);
      expect(revived.title, 'My renamed book');
      expect(revived.progress.position?.locator, 'epub:spine=0;char=40');
      expect(File(revived.localPath).existsSync(), isTrue);
      expect(await documents.count(), 1);
      expect((await bookmarks.listFor(revived.id)).single.id, bookmark.id);
      final Annotation kept = (await annotations.listFor(revived.id)).single;
      expect(kept.id, annotation.id);
      expect(kept.excerpt, 'Alpha bravo');
    },
  );

  test(
    'recognises the same content imported through a different source',
    () async {
      final File source = await sourceFile('fingerprint.epub');
      final Document first = await service.importFile(
        PickedFile(
          path: source.path,
          name: 'fingerprint.epub',
          byteSize: await source.length(),
          sourceUri: 'content://provider/one',
        ),
      );

      // A byte-identical copy is the case a content fingerprint can recognise.
      // Rebuilding the fixture would produce a different ZIP byte stream (entry
      // timestamps), which is a different file despite equivalent text.
      final File copy = await source.copy(
        p.join(temp.path, 'fingerprint-copy.epub'),
      );
      final Document second = await service.importFile(
        PickedFile(
          path: copy.path,
          name: 'fingerprint-copy.epub',
          byteSize: await copy.length(),
          sourceUri: 'content://provider/two',
        ),
      );
      expect(second.id, first.id);
      expect(await documents.count(), 1);
    },
  );
}
