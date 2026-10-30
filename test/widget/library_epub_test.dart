import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/library/data/document_repository.dart';
import 'package:paperos/features/library/domain/document.dart';
import 'package:paperos/features/library/presentation/library_screen.dart';
import 'package:paperos/theme/paper_palette.dart';
import 'package:paperos/theme/paper_theme.dart';

import '../data/support.dart';

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

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 4; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(opener),
          documentRepositoryProvider.overrideWithValue(documents),
        ],
        child: MaterialApp(
          theme: PaperTheme.build(style: PaperStyle.white),
          home: const LibraryScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> seed() async {
    await documents.insert(
      makeDocument(
        id: 'epub',
        title: 'An EPUB',
        format: DocumentFormat.epub,
        pageCount: 10,
      ).copyWith(author: 'Ada Author'),
    );
    await documents.insert(
      makeDocument(
        id: 'pdf',
        title: 'A PDF',
        format: DocumentFormat.pdf,
        pageCount: 10,
      ),
    );
    await documents.insert(
      makeDocument(
        id: 'text',
        title: 'A Text',
        format: DocumentFormat.text,
        pageCount: null,
      ),
    );
  }

  testWidgets('shows every format and status filter without a second nav bar', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(tester);

    for (final String label in <String>[
      'All',
      'EPUB',
      'PDF',
      'TXT',
      'Recent',
      'Favorites',
      'Unread',
      'In progress',
      'Completed',
    ]) {
      expect(find.text(label), findsWidgets, reason: 'missing $label filter');
    }
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets('filters EPUB and searches authors', (WidgetTester tester) async {
    await tester.runAsync(seed);
    await pumpLibrary(tester);

    expect(find.text('An EPUB'), findsOneWidget);
    expect(find.text('A PDF'), findsOneWidget);

    await tester.tap(find.text('EPUB').first);
    await settle(tester);
    expect(find.text('An EPUB'), findsOneWidget);
    expect(find.text('A PDF'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'ada author');
    await settle(tester);
    expect(find.text('An EPUB'), findsOneWidget);
    expect(find.text('A Text'), findsNothing);
  });

  testWidgets('sorts the library by title from the restrained menu', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(seed);
    await pumpLibrary(tester);

    await tester.tap(find.byTooltip('Sort library'));
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Title'), findsOneWidget);
    await tester.tap(find.text('Title'), warnIfMissed: false);
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester);

    final double podcast = tester.getTopLeft(find.text('A PDF')).dy;
    final double textY = tester.getTopLeft(find.text('A Text')).dy;
    final double epubY = tester.getTopLeft(find.text('An EPUB')).dy;
    expect(podcast, lessThan(textY));
    expect(textY, lessThan(epubY));
  });
}
