import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/platform/installed_app.dart';
import 'package:paperos/features/launcher/presentation/apps_screen.dart';
import 'package:paperos/features/launcher/presentation/installed_app_icon.dart';
import 'package:paperos/features/settings/data/settings_repository.dart';
import 'package:paperos/features/settings/domain/app_settings.dart';
import 'package:paperos/theme/paper_palette.dart';
import 'package:paperos/theme/paper_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_launcher_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final InstalledApp reader = fakeApp('com.example.reader', label: 'Reader');
  final InstalledApp notes = fakeApp('com.example.notes', label: 'Notes');

  Future<void> pumpApps(
    WidgetTester tester,
    FakeLauncherService launcher, {
    LauncherSettings launcherSettings = const LauncherSettings(
      showSystemApps: true,
    ),
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await SettingsRepository(preferences)
        .save(AppSettings(launcher: launcherSettings));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          launcherServiceProvider.overrideWithValue(launcher),
        ],
        child: MaterialApp(
          theme: PaperTheme.build(style: PaperStyle.white),
          home: const AppsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('shows pinned and recent shortcuts above the full list', (
    WidgetTester tester,
  ) async {
    await pumpApps(
      tester,
      FakeLauncherService(apps: <InstalledApp>[reader, notes]),
      launcherSettings: const LauncherSettings(
        showSystemApps: true,
        favoritePackages: <String>['com.example.notes'],
        recentPackages: <String>['com.example.reader'],
      ),
    );

    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('All apps'), findsOneWidget);
    expect(find.text('Reader'), findsWidgets);
    expect(find.text('Notes'), findsWidgets);
    expect(find.byTooltip('Unpin Notes'), findsOneWidget);
    expect(find.byTooltip('Pin Reader'), findsOneWidget);
  });

  testWidgets('tapping a row launches it and pinning is reversible', (
    WidgetTester tester,
  ) async {
    final FakeLauncherService launcher = FakeLauncherService(
      apps: <InstalledApp>[reader, notes],
    );
    await pumpApps(tester, launcher);

    await tester.tap(find.text('Reader'));
    await tester.pump();
    expect(launcher.launched, <InstalledApp>[reader]);

    await tester.tap(find.byTooltip('Pin Reader'));
    await tester.pump();
    expect(find.byTooltip('Unpin Reader'), findsOneWidget);

    await tester.tap(find.byTooltip('Unpin Reader'));
    await tester.pump();
    expect(find.byTooltip('Pin Reader'), findsOneWidget);
  });

  testWidgets('refresh asks the platform for a fresh catalogue', (
    WidgetTester tester,
  ) async {
    final FakeLauncherService launcher = FakeLauncherService(
      apps: <InstalledApp>[reader],
    );
    await pumpApps(tester, launcher);
    expect(launcher.loadCount, 1);

    await tester.tap(find.byTooltip('Refresh apps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(launcher.loadCount, 2);
  });

  testWidgets('a restricted empty catalogue explains itself', (
    WidgetTester tester,
  ) async {
    await pumpApps(
      tester,
      FakeLauncherService(apps: const <InstalledApp>[], restricted: true),
    );

    expect(find.text('The app list looks incomplete'), findsOneWidget);
    expect(find.text('Reload'), findsOneWidget);
  });

  testWidgets('the show-icons preference reaches every icon', (
    WidgetTester tester,
  ) async {
    await pumpApps(
      tester,
      FakeLauncherService(apps: <InstalledApp>[reader]),
      launcherSettings: const LauncherSettings(
        showIcons: false,
        favoritePackages: <String>['com.example.reader'],
      ),
    );

    final Iterable<InstalledAppIcon> icons = tester
        .widgetList<InstalledAppIcon>(find.byType(InstalledAppIcon));
    expect(icons, isNotEmpty);
    expect(icons.every((InstalledAppIcon icon) => icon.showIcon), isFalse);
  });
}
