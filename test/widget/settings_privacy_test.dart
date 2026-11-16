import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/settings/presentation/settings_screen.dart';
import 'package:paperos/theme/paper_palette.dart';
import 'package:paperos/theme/paper_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_launcher_service.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabaseOpener opener;

  setUp(() {
    opener = AppDatabaseOpener(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await (await opener.database).close();
  });

  testWidgets('Settings exposes an in-app privacy statement', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appDatabaseProvider.overrideWithValue(opener),
          launcherServiceProvider.overrideWithValue(FakeLauncherService()),
        ],
        child: MaterialApp(
          theme: PaperTheme.build(style: PaperStyle.white),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Privacy'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Privacy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('On this device'), findsOneWidget);
    expect(find.text('No network, no account'), findsOneWidget);
    expect(find.text('Backups are not encrypted'), findsOneWidget);
    expect(
      find.textContaining('not encrypted or digitally signed'),
      findsOneWidget,
    );
  });
}
