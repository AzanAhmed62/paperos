import 'dart:typed_data';

import '../../../core/platform/installed_app.dart';
import '../../../core/platform/launcher_service.dart';

/// Filters and orders the installed app list for the app drawer.
///
/// Deliberately a pure function over an already-loaded list: sorting and
/// searching must never touch a platform channel, so the drawer stays instant
/// and the logic is unit testable without a device.
abstract final class AppCatalogQuery {
  /// Orders apps for display: pinned favourites first (in pin order), then
  /// user-installed apps, then system apps, each group alphabetical.
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

    final Map<String, int> pinOrder = <String, int>{
      for (int i = 0; i < favoritePackages.length; i++) favoritePackages[i]: i,
    };

    final List<InstalledApp> sorted = List<InstalledApp>.of(visible);
    sorted.sort((InstalledApp a, InstalledApp b) {
      final int pinA = pinOrder[a.packageName] ?? 1 << 20;
      final int pinB = pinOrder[b.packageName] ?? 1 << 20;
      if (pinA != pinB) return pinA.compareTo(pinB);
      if (a.isSystem != b.isSystem) return a.isSystem ? 1 : -1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return sorted;
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
