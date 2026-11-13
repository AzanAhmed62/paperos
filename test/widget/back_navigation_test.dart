import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/paper_app.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/platform/file_browser_service.dart';
import 'package:paperos/core/platform/installed_app.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/files/data/location_repository.dart';
import 'package:paperos/features/files/domain/browsed_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_launcher_service.dart';

/// A browser that answers from a fixed map, so the Files folder stack can be
/// exercised without Android's Storage Access Framework.
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

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 4; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    FileBrowserService? browser,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appDatabaseProvider.overrideWithValue(opener),
          locationRepositoryProvider.overrideWithValue(locations),
          launcherServiceProvider.overrideWithValue(
            FakeLauncherService(
              apps: <InstalledApp>[
                fakeApp('com.example.reader', label: 'Reader'),
              ],
            ),
          ),
          fileBrowserServiceProvider.overrideWithValue(
            browser ?? _FakeBrowser(),
          ),
        ],
        child: const PaperApp(),
      ),
    );
    await settle(tester);
  }

  Finder destination(String path) => find.byKey(ValueKey<String>('dest-$path'));

  Future<void> androidBack(WidgetTester tester) async {
    await WidgetsBinding.instance.handlePopRoute();
    await tester.pump();
    await settle(tester);
  }

  testWidgets('Back from a primary surface returns to Paper Home', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(destination('library'));
    await settle(tester);
    expect(find.text('Your library is empty'), findsOneWidget);

    await androidBack(tester);
    expect(find.text('PaperOS'), findsOneWidget);
    expect(find.text('Your library is empty'), findsNothing);
  });

  testWidgets('Back on Paper Home is consumed and does not leave the app', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('PaperOS'), findsOneWidget);

    await androidBack(tester);

    // The Home header is still visible; no error route or blank surface was
    // pushed in its place.
    expect(find.text('PaperOS'), findsOneWidget);
    expect(find.text('PaperOS cannot open this yet'), findsNothing);
  });

  testWidgets('an overlay closes before the primary surface changes', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Apps'));
    await settle(tester);
    expect(find.text('Search apps'), findsOneWidget);

    await androidBack(tester);
    expect(find.text('Search apps'), findsNothing);
    expect(find.text('PaperOS'), findsOneWidget);
  });

  testWidgets('Files folder Back steps out, then returns to Home', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(
      () => locations.add(label: 'Books', uri: 'content://tree/books'),
    );

    await pumpApp(
      tester,
      browser: _FakeBrowser(
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
      ),
    );

    await tester.tap(destination('files'));
    await settle(tester);
    expect(find.text('Books'), findsOneWidget);

    await tester.tap(find.text('Books'));
    await settle(tester);
    await tester.tap(find.text('Novels'));
    await settle(tester);
    expect(find.text('This folder is empty'), findsOneWidget);

    // First Back leaves the subfolder but stays in the location root.
    await androidBack(tester);
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('This folder is empty'), findsNothing);

    // Second Back leaves the location root for the granted-folder list.
    await androidBack(tester);
    expect(find.text('Novels'), findsNothing);

    // Third Back leaves the Files destination for Paper Home.
    await androidBack(tester);
    expect(find.text('PaperOS'), findsOneWidget);
    expect(find.text('Books'), findsNothing);
  });
}
