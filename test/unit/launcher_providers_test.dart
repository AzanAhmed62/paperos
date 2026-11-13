import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/platform/installed_app.dart';
import 'package:paperos/features/launcher/application/launcher_providers.dart';
import 'package:paperos/features/settings/application/settings_controller.dart';
import 'package:paperos/features/settings/domain/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_launcher_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
  });

  ProviderContainer makeContainer(FakeLauncherService launcher) {
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        launcherServiceProvider.overrideWithValue(launcher),
      ],
    );
  }

  final InstalledApp reader = fakeApp('com.example.reader', label: 'Reader');
  final InstalledApp notes = fakeApp('com.example.notes', label: 'Notes');
  final InstalledApp settingsApp = fakeApp(
    'com.android.settings',
    label: 'Settings',
    isSystem: true,
  );

  test('orders pinned apps first, then user apps, then system apps', () async {
    final FakeLauncherService launcher = FakeLauncherService(
      apps: <InstalledApp>[settingsApp, notes, reader],
    );
    final ProviderContainer container = makeContainer(launcher);
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).setFavorites(<String>[
      'com.example.notes',
    ]);
    await container.read(settingsProvider.notifier).setShowSystemApps(true);

    final List<InstalledApp> ordered = await container.read(
      installedAppsProvider.future,
    );

    expect(ordered.map((InstalledApp app) => app.packageName), <String>[
      'com.example.notes',
      'com.example.reader',
      'com.android.settings',
    ]);

    await container.read(settingsProvider.notifier).setShowSystemApps(false);
    final List<InstalledApp> userOnly = await container.read(
      installedAppsProvider.future,
    );
    expect(userOnly, hasLength(2));
    expect(userOnly.every((InstalledApp app) => !app.isSystem), isTrue);
  });

  test(
    'favourites resolve in pin order and skip uninstalled packages',
    () async {
      final FakeLauncherService launcher = FakeLauncherService(
        apps: <InstalledApp>[reader, notes],
      );
      final ProviderContainer container = makeContainer(launcher);
      addTearDown(container.dispose);

      await container.read(settingsProvider.notifier).setFavorites(<String>[
        'com.example.notes',
        'com.example.gone',
        'com.example.reader',
      ]);
      // Reading the snapshot is what fills the package index.
      await container.read(appCatalogSnapshotProvider.future);

      expect(
        container
            .read(favoriteAppsProvider)
            .map((InstalledApp app) => app.packageName),
        <String>['com.example.notes', 'com.example.reader'],
      );
    },
  );

  test('recents are newest first, deduplicated and bounded', () async {
    final FakeLauncherService launcher = FakeLauncherService(
      apps: <InstalledApp>[reader, notes],
    );
    final ProviderContainer container = makeContainer(launcher);
    addTearDown(container.dispose);

    final SettingsController settings = container.read(
      settingsProvider.notifier,
    );
    await settings.recordRecentApp('com.example.reader');
    await settings.recordRecentApp('com.example.notes');
    await settings.recordRecentApp('com.example.reader');

    expect(container.read(settingsProvider).launcher.recentPackages, <String>[
      'com.example.reader',
      'com.example.notes',
    ]);

    await container.read(appCatalogSnapshotProvider.future);
    expect(container.read(recentAppsProvider), hasLength(2));

    for (int i = 0; i < LauncherSettings.maxRecents + 4; i++) {
      await settings.recordRecentApp('com.example.app$i');
    }
    expect(
      container.read(settingsProvider).launcher.recentPackages,
      hasLength(LauncherSettings.maxRecents),
    );
  });

  test(
    'launching records a recent only after the platform accepts it',
    () async {
      final FakeLauncherService launcher = FakeLauncherService(
        apps: <InstalledApp>[reader],
      );
      final ProviderContainer container = makeContainer(launcher);
      addTearDown(container.dispose);

      await container.read(launcherActionsProvider).launch(reader);

      expect(launcher.launched, <InstalledApp>[reader]);
      expect(container.read(settingsProvider).launcher.recentPackages, <String>[
        'com.example.reader',
      ]);

      launcher.failLaunch = true;
      await expectLater(
        container.read(launcherActionsProvider).launch(notes),
        throwsA(anything),
      );
      expect(container.read(settingsProvider).launcher.recentPackages, <String>[
        'com.example.reader',
      ]);
    },
  );

  test('pinning is reversible and clearRecents empties the strip', () async {
    final FakeLauncherService launcher = FakeLauncherService(
      apps: <InstalledApp>[reader],
    );
    final ProviderContainer container = makeContainer(launcher);
    addTearDown(container.dispose);

    final LauncherActions actions = container.read(launcherActionsProvider);
    await actions.toggleFavorite(reader);
    expect(container.read(settingsProvider).launcher.favoritePackages, <String>[
      'com.example.reader',
    ]);

    await actions.toggleFavorite(reader);
    expect(container.read(settingsProvider).launcher.favoritePackages, isEmpty);

    await actions.launch(reader);
    expect(
      container.read(settingsProvider).launcher.recentPackages,
      isNotEmpty,
    );
    await actions.clearRecents();
    expect(container.read(settingsProvider).launcher.recentPackages, isEmpty);
  });

  test('refresh drops the cache and asks the platform again', () async {
    final FakeLauncherService launcher = FakeLauncherService(
      apps: <InstalledApp>[reader],
    );
    final ProviderContainer container = makeContainer(launcher);
    addTearDown(container.dispose);

    await container.read(installedAppsProvider.future);
    expect(launcher.loadCount, 1);

    container.read(launcherActionsProvider).refreshApps();
    await container.read(installedAppsProvider.future);
    expect(launcher.loadCount, 2);
  });

  test('the platform restricted flag is exposed to the drawer', () async {
    final FakeLauncherService launcher = FakeLauncherService(
      apps: const <InstalledApp>[],
      restricted: true,
    );
    final ProviderContainer container = makeContainer(launcher);
    addTearDown(container.dispose);

    await container.read(appCatalogSnapshotProvider.future);
    expect(container.read(appCatalogRestrictedProvider), isTrue);
  });
}
