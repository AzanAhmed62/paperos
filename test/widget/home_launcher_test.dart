import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/platform/installed_app.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/core/utils/date_format.dart';
import 'package:paperos/features/home/presentation/paper_home_screen.dart';
import 'package:paperos/features/settings/application/settings_controller.dart';
import 'package:paperos/features/settings/data/settings_repository.dart';
import 'package:paperos/features/settings/domain/app_settings.dart';
import 'package:paperos/theme/paper_palette.dart';
import 'package:paperos/theme/paper_space.dart';
import 'package:paperos/theme/paper_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_launcher_service.dart';

void main() {
  sqfliteFfiInit();

  final InstalledApp reader = fakeApp('com.example.reader', label: 'Reader');

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

  /// Gives sqflite-ffi work and the settings write a chance to finish.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 4; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    required FakeLauncherService launcher,
    AppSettings settings = const AppSettings(),
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await SettingsRepository(preferences).save(settings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appDatabaseProvider.overrideWithValue(opener),
          launcherServiceProvider.overrideWithValue(launcher),
        ],
        child: MaterialApp(
          theme: PaperTheme.build(style: PaperStyle.white),
          home: const PaperHomeScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  /// The clock Text, matched by shape rather than by a value that can tick
  /// over between the expectation and the build.
  Finder clockText() {
    return find.byWidgetPredicate(
      (Widget widget) =>
          widget is Text &&
          widget.data != null &&
          RegExp(r'^\d{2}:\d{2}$').hasMatch(widget.data!),
    );
  }

  double clockTopPadding(WidgetTester tester) {
    final Finder padding = find
        .ancestor(of: clockText(), matching: find.byType(Padding))
        .first;
    return (tester.widget<Padding>(padding).padding as EdgeInsets).top;
  }

  testWidgets('home shows launcher quick actions, pins and role status', (
    WidgetTester tester,
  ) async {
    await pumpHome(
      tester,
      launcher: FakeLauncherService(apps: <InstalledApp>[reader], home: true),
      settings: const AppSettings(
        launcher: LauncherSettings(
          showSystemApps: true,
          favoritePackages: <String>['com.example.reader'],
        ),
      ),
    );

    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Apps'), findsOneWidget);
    expect(find.text('New note'), findsOneWidget);
    expect(find.text('New task'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Pinned'), 300);
    await tester.pump();
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Reader'), findsOneWidget);

    // PaperOS already holds the HOME role, so there is no setup prompt.
    expect(find.text('Make PaperOS your home app'), findsNothing);
    expect(find.text('Set up'), findsNothing);
  });

  testWidgets(
    'uses the stored heading without duplicate Search or Apps icons',
    (WidgetTester tester) async {
      await pumpHome(
        tester,
        launcher: FakeLauncherService(apps: <InstalledApp>[reader], home: true),
        settings: const AppSettings(
          home: HomeSettings(displayName: 'Quiet Hours'),
        ),
      );

      expect(find.text('Quiet Hours'), findsOneWidget);
      expect(find.text('PaperOS'), findsNothing);
      // One Search and one Apps entry, both in the four-action row. The header
      // must not repeat either action as an icon.
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Apps'), findsOneWidget);
      expect(find.byTooltip('Search'), findsNothing);
      expect(find.byTooltip('Apps'), findsNothing);
    },
  );

  testWidgets('hiding Search leaves Apps as the only app entry point', (
    WidgetTester tester,
  ) async {
    await pumpHome(
      tester,
      launcher: FakeLauncherService(home: true),
      settings: const AppSettings(
        home: HomeSettings(hiddenSections: <HomeSection>{HomeSection.search}),
      ),
    );

    expect(find.text('Search'), findsNothing);
    expect(find.text('Apps'), findsOneWidget);
    expect(find.text('New note'), findsOneWidget);
    expect(find.text('New task'), findsOneWidget);
  });

  testWidgets('shows one contextual HOME-role prompt when not the default', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, launcher: FakeLauncherService(home: false));

    await tester.scrollUntilVisible(
      find.text('Make PaperOS your home app'),
      300,
    );
    await tester.pump();

    expect(find.text('Make PaperOS your home app'), findsOneWidget);
    expect(find.text('Pressing Home returns to this screen.'), findsOneWidget);
    expect(find.text('Set up'), findsOneWidget);
    // The old duplicated launcher-status rows are gone.
    expect(find.text('PaperOS is not your home app'), findsNothing);
    expect(find.text('Open the app drawer'), findsNothing);
  });

  testWidgets('date visibility and density follow the Home preferences', (
    WidgetTester tester,
  ) async {
    await pumpHome(
      tester,
      launcher: FakeLauncherService(home: false),
      settings: const AppSettings(
        home: HomeSettings(showDate: true, density: HomeDensity.comfortable),
      ),
    );

    final String today = formatLongDate(DateTime.now());
    // One in the clock block and one in the Today section heading.
    expect(find.text(today), findsNWidgets(2));
    expect(clockTopPadding(tester), PaperSpace.xl);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(PaperHomeScreen)),
    );
    await container.read(settingsProvider.notifier).setShowDate(false);
    await container
        .read(settingsProvider.notifier)
        .setHomeDensity(HomeDensity.compact);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(today), findsOneWidget);
    expect(clockTopPadding(tester), PaperSpace.lg);
  });
}
