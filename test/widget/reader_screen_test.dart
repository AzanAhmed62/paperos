import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/errors/paper_exception.dart';
import 'package:paperos/core/platform/pdf_service.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/core/storage/app_storage.dart';
import 'package:paperos/features/library/data/document_repository.dart';
import 'package:paperos/features/library/domain/document.dart';
import 'package:paperos/features/reader/presentation/reader_screen.dart';
import 'package:paperos/theme/paper_palette.dart';
import 'package:paperos/theme/paper_theme.dart';
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

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temp = await Directory.systemTemp.createTemp('paperos_reader_widget_');
    opener = openTestDatabase();
    documents = DocumentRepository(opener);
  });

  tearDown(() async {
    await documents.dispose();
    await (await opener.database).close();
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<Document> seed() async {
    final File file = File('${temp.path}/book.epub');
    await file.writeAsBytes(buildEpubFixture(), flush: true);
    final Document document = makeDocument(
      id: 'book',
      title: 'A Test Book',
      format: DocumentFormat.epub,
      pageCount: 1,
      localPath: file.path,
    );
    await documents.insert(document);
    return document;
  }

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('opens an EPUB in the real reader chrome', (
    WidgetTester tester,
  ) async {
    final Document document =
        await tester.runAsync(seed) ?? (throw StateError('seed failed'));
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appDatabaseProvider.overrideWithValue(opener),
          documentRepositoryProvider.overrideWithValue(documents),
          appStorageProvider.overrideWithValue(
            AppStorage(rootOverride: () async => temp),
          ),
          pdfServiceProvider.overrideWithValue(_NoPdfService()),
        ],
        child: MaterialApp(
          theme: PaperTheme.build(style: PaperStyle.white),
          home: ReaderScreen(documentId: document.id),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('A Test Book'), findsOneWidget);
    final SelectableText pageText = tester.widget<SelectableText>(
      find.byType(SelectableText).first,
    );
    expect(pageText.textSpan?.toPlainText(), contains('Alpha bravo'));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Reader menu'));
    await tester.pump();
    expect(find.text('Contents'), findsOneWidget);
    expect(find.textContaining('Bookmarks'), findsOneWidget);
    expect(find.textContaining('Annotations'), findsOneWidget);
    expect(find.text('Reading settings'), findsOneWidget);
  });
}
