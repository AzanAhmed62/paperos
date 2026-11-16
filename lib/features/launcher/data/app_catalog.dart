import 'dart:typed_data';

import '../../../core/platform/installed_app.dart';
import '../../../core/platform/launcher_service.dart';

/// Filters and orders the installed app list for the app drawer.
///
/// Deliberately a pure function over an already-loaded list: sorting and
/// searching must never touch a platform channel, so the drawer stays instant
/// and the logic is unit testable without a device.
abstract final class AppCatalogQuery {
  /// Orders apps for display.
  ///
  /// One canonical rule: pinned apps first in the user's pin order, then every
  /// remaining visible app in one alphabetical sequence. System status is a
  /// filter, never a second sorting group, so enabling system apps does not
  /// create a second A–Z block after the user-installed apps.
  static List<InstalledApp> arrange(
    List<InstalledApp> apps, {
    required List<String> favoritePackages,
    required bool showSystemApps,
  }) {
    final List<InstalledApp> visible = showSystemApps
        ? apps
        : apps
              .where((InstalledApp app) => !app.isSystem)
              .toList(growable: false);

    // A launcher shows one icon per package. If the platform ever reports two
    // launchable activities for one package, keep a deterministic representative
    // rather than rendering a duplicate row.
    final Map<String, InstalledApp> byPackage = <String, InstalledApp>{};
    for (final InstalledApp app in visible) {
      final InstalledApp? current = byPackage[app.packageName];
      if (current == null ||
          app.activityName.compareTo(current.activityName) < 0) {
        byPackage[app.packageName] = app;
      }
    }

    final List<InstalledApp> pinned = <InstalledApp>[];
    final Set<String> pinnedPackages = <String>{};
    for (final String packageName in favoritePackages) {
      final InstalledApp? app = byPackage[packageName];
      if (app != null && pinnedPackages.add(packageName)) pinned.add(app);
    }

    final List<InstalledApp> remaining = byPackage.values
        .where((InstalledApp app) => !pinnedPackages.contains(app.packageName))
        .toList();
    remaining.sort(_compare);

    return <InstalledApp>[...pinned, ...remaining];
  }

  /// Case-insensitive label, then package, then activity. Every tie-break is
  /// deterministic so repeated reads of the same catalogue never reorder rows.
  static int _compare(InstalledApp a, InstalledApp b) {
    final int byLabel = _normalisedLabel(a).compareTo(_normalisedLabel(b));
    if (byLabel != 0) return byLabel;
    final int byPackage = a.packageName.compareTo(b.packageName);
    if (byPackage != 0) return byPackage;
    return a.activityName.compareTo(b.activityName);
  }

  static String _normalisedLabel(InstalledApp app) {
    final String label = app.label.trim();
    return (label.isEmpty ? app.packageName : label).toLowerCase();
  }

  /// Case-insensitive substring search over label then package name.
  static List<InstalledApp> search(List<InstalledApp> apps, String query) {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) return apps;
    return apps
        .where((InstalledApp app) {
          return app.label.toLowerCase().contains(needle) ||
              app.packageName.toLowerCase().contains(needle);
        })
        .toList(growable: false);
  }
}

/// Holds the one expensive thing about being a launcher: the app list, plus the
/// rendered icons.
class AppCatalogCache {
  AppCatalogCache(this._service);

  final LauncherService _service;

  AppCatalogSnapshot? _snapshot;
  final Map<String, Uint8List> _icons = <String, Uint8List>{};

  AppCatalogSupport get support => _service.support;

  bool get isLoaded => _snapshot != null;

  bool get restricted => _snapshot?.restricted ?? false;

  /// Loads the app list once per session.
  Future<AppCatalogSnapshot> apps({bool force = false}) async {
    final AppCatalogSnapshot? cached = _snapshot;
    if (cached != null && !force) return cached;
    final AppCatalogSnapshot loaded = await _service.loadApps();
    _snapshot = loaded;
    return loaded;
  }

  /// Icon bytes for [packageName], or null when the platform cannot draw it.
  Future<Uint8List?> icon(String packageName) async {
    final Uint8List? cached = _icons[packageName];
    if (cached != null) return cached;
    final Uint8List? bytes = await _service.loadIcon(packageName);
    if (bytes != null && bytes.isNotEmpty) _icons[packageName] = bytes;
    return bytes;
  }

  /// Drops the app list, e.g. after the user installs or removes something.
  void invalidate() => _snapshot = null;
}
