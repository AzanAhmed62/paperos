import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/platform/file_browser_service.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/files/data/location_repository.dart';
import 'package:paperos/features/files/domain/browsed_entry.dart';
import 'package:paperos/features/files/presentation/files_screen.dart';
import 'package:paperos/theme/paper_palette.dart';
import 'package:paperos/theme/paper_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A file browser that answers from a fixed map instead of Android.
class _FakeBrowser implements FileBrowserService {
  _FakeBrowser({this.children = const <String, List<BrowsedEntry>>{}});

  final Map<String, List<BrowsedEntry>> children;

  @override
  bool get isSupported => true;

  @override
  Future<BrowsedLocation?> pickLocation() async => null;

  @override
  Future<List<BrowsedEntry>> listChildren({
    required String treeUri,
    String? directoryUri,
  }) async => children[directoryUri ?? treeUri] ?? const <BrowsedEntry>[];

  @override
  Future<String> materialise(BrowsedEntry entry) async => '/tmp/${entry.name}';

  @override
  Future<void> releaseLocation(BrowsedLocation location) async {}

  @override
  Future<ExternalDocument?> takeExternalDocument() async => null;

  @override
  void onExternalDocument(void Function(ExternalDocument document) handler) {}
}

void main() {
  sqfliteFfiInit();

  late AppDatabaseOpener opener;
  late LocationRepository locations;

  setUp(() {
    opener = AppDatabaseOpener(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    locations = LocationRepository(opener);
  });

  tearDown(() async {
    await locations.dispose();
    await (await opener.database).close();
  });

  /// Gives real sqflite-ffi work a chance to finish, then lets the resulting
  /// provider rebuild reach the widget tree. More than one cycle is needed
  /// because the pump that flushes an invalidation can start another read.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpFiles(WidgetTester tester, _FakeBrowser browser) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(opener),
          locationRepositoryProvider.overrideWithValue(locations),
          fileBrowserServiceProvider.overrideWithValue(browser),
        ],
        child: MaterialApp(
          theme: PaperTheme.build(style: PaperStyle.white),
          home: const FilesScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('explains itself when no folders have been added', (
    WidgetTester tester,
  ) async {
    await pumpFiles(tester, _FakeBrowser());

    expect(find.text('No folders yet'), findsOneWidget);
    expect(find.text('Add a folder'), findsWidgets);
  });

  testWidgets('lists granted folders and browses into them', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(
      () => locations.add(label: 'Books', uri: 'content://tree/books'),
    );

    final _FakeBrowser browser = _FakeBrowser(
      children: <String, List<BrowsedEntry>>{
        'content://tree/books': const <BrowsedEntry>[
          BrowsedEntry(
            uri: 'content://doc/novels',
            name: 'Novels',
            isDirectory: true,
          ),
          BrowsedEntry(
            uri: 'content://doc/paper',
            name: 'paper.pdf',
            isDirectory: false,
            byteSize: 2048,
          ),
          BrowsedEntry(
            uri: 'content://doc/archive',
            name: 'archive.zip',
            isDirectory: false,
          ),
        ],
        'content://doc/novels': const <BrowsedEntry>[],
      },
    );

    await pumpFiles(tester, browser);

    // The granted folder is shown, then opened.
    expect(find.text('Books'), findsOneWidget);
    await tester.tap(find.text('Books'));
    await settle(tester);

    expect(find.text('Novels'), findsOneWidget);
    expect(find.text('paper.pdf'), findsOneWidget);
    expect(find.text('Not supported'), findsOneWidget);

    // An unsupported file states so rather than opening.
    await tester.tap(find.text('archive.zip'));
    await settle(tester);
    expect(find.text('PaperOS cannot open archive.zip.'), findsOneWidget);
  });

  testWidgets('opens and closes a subfolder', (WidgetTester tester) async {
    await tester.runAsync(
      () => locations.add(label: 'Books', uri: 'content://tree/books'),
    );

    final _FakeBrowser browser = _FakeBrowser(
      children: <String, List<BrowsedEntry>>{
        'content://tree/books': const <BrowsedEntry>[
          BrowsedEntry(
            uri: 'content://doc/novels',
            name: 'Novels',
            isDirectory: true,
          ),
        ],
        'content://doc/novels': const <BrowsedEntry>[],
      },
    );

    await pumpFiles(tester, browser);
    await tester.tap(find.text('Books'));
    await settle(tester);
    await tester.tap(find.text('Novels'));
    await settle(tester);

    expect(find.text('This folder is empty'), findsOneWidget);

    // Back returns to the location list.
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('Books'), findsOneWidget);
  });
}
