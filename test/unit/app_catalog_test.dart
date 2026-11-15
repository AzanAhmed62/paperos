import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/platform/installed_app.dart';
import 'package:paperos/features/launcher/data/app_catalog.dart';

InstalledApp _app(
  String packageName, {
  String? label,
  String? activityName,
  bool isSystem = false,
}) {
  return InstalledApp(
    packageName: packageName,
    activityName: activityName ?? '$packageName.MainActivity',
    label: label ?? packageName.split('.').last,
    isSystem: isSystem,
  );
}

List<String> _packages(List<InstalledApp> apps) =>
    apps.map((InstalledApp app) => app.packageName).toList(growable: false);

void main() {
  group('AppCatalogQuery.arrange', () {
    test('pins first in pin order, then one case-insensitive A–Z list', () {
      final InstalledApp zebra = _app('com.example.zebra', label: 'Zebra');
      final InstalledApp apple = _app('com.example.apple', label: 'apple');
      final InstalledApp calendar = _app(
        'com.android.calendar',
        label: 'Calendar',
        isSystem: true,
      );
      final InstalledApp reader = _app('com.example.reader', label: 'Reader');

      final List<InstalledApp> ordered = AppCatalogQuery.arrange(
        <InstalledApp>[zebra, calendar, reader, apple],
        favoritePackages: <String>['com.example.zebra', 'com.example.apple'],
        showSystemApps: true,
      );

      expect(_packages(ordered), <String>[
        'com.example.zebra',
        'com.example.apple',
        'com.android.calendar',
        'com.example.reader',
      ]);
    });

    test('system apps are filtered, not given a second sorting group', () {
      final InstalledApp calendar = _app(
        'com.android.calendar',
        label: 'Calendar',
        isSystem: true,
      );
      final InstalledApp reader = _app('com.example.reader', label: 'Reader');
      final InstalledApp zebra = _app('com.example.zebra', label: 'Zebra');

      expect(
        _packages(
          AppCatalogQuery.arrange(
            <InstalledApp>[zebra, calendar, reader],
            favoritePackages: const <String>[],
            showSystemApps: false,
          ),
        ),
        <String>['com.example.reader', 'com.example.zebra'],
      );

      expect(
        _packages(
          AppCatalogQuery.arrange(
            <InstalledApp>[zebra, calendar, reader],
            favoritePackages: const <String>[],
            showSystemApps: true,
          ),
        ),
        <String>[
          'com.android.calendar',
          'com.example.reader',
          'com.example.zebra',
        ],
      );
    });

    test('deduplicates a package and keeps a deterministic activity', () {
      final InstalledApp second = _app(
        'com.example.reader',
        label: 'Reader',
        activityName: 'com.example.reader.Second',
      );
      final InstalledApp first = _app(
        'com.example.reader',
        label: 'Reader',
        activityName: 'com.example.reader.First',
      );

      final List<InstalledApp> ordered = AppCatalogQuery.arrange(
        <InstalledApp>[second, first],
        favoritePackages: const <String>[],
        showSystemApps: true,
      );

      expect(ordered, hasLength(1));
      expect(ordered.single.activityName, 'com.example.reader.First');
    });

    test('breaks label ties by package, then activity', () {
      final InstalledApp b = _app('com.example.b', label: 'Same');
      final InstalledApp a = _app('com.example.a', label: 'Same');
      final InstalledApp c = _app(
        'com.example.a',
        label: 'Same',
        activityName: 'com.example.a.Other',
      );

      final List<InstalledApp> ordered = AppCatalogQuery.arrange(
        <InstalledApp>[b, c, a],
        favoritePackages: const <String>[],
        showSystemApps: true,
      );

      expect(_packages(ordered), <String>['com.example.a', 'com.example.b']);
      expect(ordered.first.activityName, 'com.example.a.MainActivity');
    });

    test('ignores pins for apps that are no longer installed', () {
      final InstalledApp reader = _app('com.example.reader', label: 'Reader');

      final List<InstalledApp> ordered = AppCatalogQuery.arrange(
        <InstalledApp>[reader],
        favoritePackages: <String>['com.example.gone', 'com.example.reader'],
        showSystemApps: true,
      );

      expect(_packages(ordered), <String>['com.example.reader']);
    });

    test('an empty label sorts by package rather than to the top', () {
      final InstalledApp blank = _app('com.example.zblank', label: '');
      final InstalledApp alpha = _app('com.example.alpha', label: 'Alpha');

      final List<InstalledApp> ordered = AppCatalogQuery.arrange(
        <InstalledApp>[blank, alpha],
        favoritePackages: const <String>[],
        showSystemApps: true,
      );

      expect(_packages(ordered), <String>[
        'com.example.alpha',
        'com.example.zblank',
      ]);
    });
  });
}
