import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/paper_app.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Boots the real [PaperApp] against an in-memory database and mock settings.
///
/// This is deliberately end-to-end at the widget layer rather than a unit test
/// of one screen: it is the only test that proves the root provider wiring, the
/// router, and the destination shell agree with each other.
void main() {
  sqfliteFfiInit();

  late AppDatabaseOpener opener;

  Future<void> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    opener = AppDatabaseOpener(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appDatabaseProvider.overrideWithValue(opener),
        ],
        child: const PaperApp(),
      ),
    );
    // One pump to resolve the async library/task providers, one more to draw.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  tearDown(() async {
    await (await opener.database).close();
  });

  Finder destination(String path) => find.byKey(ValueKey<String>('dest-$path'));

  /// Lets real asynchronous work (the sqflite isolate, timers) run, which the
  /// fake-async widget clock deliberately does not advance on its own.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 3; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('boots to Paper Home with the five destinations', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    for (final String path in <String>[
      'home',
      'library',
      'files',
      'notes',
      'settings',
    ]) {
      expect(destination(path), findsOneWidget, reason: 'missing $path tab');
    }
  });

  testWidgets('navigates to the Library and back to Home', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(destination('library'));
    await tester.pump();
    await settle(tester);

    // The empty library explains itself rather than showing a blank screen.
    expect(find.text('Your library is empty'), findsOneWidget);

    await tester.tap(destination('home'));
    await tester.pump();
    await settle(tester);
    expect(destination('home'), findsOneWidget);
  });
}
