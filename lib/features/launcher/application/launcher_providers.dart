import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/platform/installed_app.dart';
import '../../launcher/data/app_catalog.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/app_settings.dart';

/// The app drawer's search text.
///
/// Separate from the library search: a launcher drawer and a document list
/// are different jobs, and sharing one query would make the library jump to a
/// search state just because the user typed in the drawer.
class AppSearchController extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;

  void clear() => state = '';
}

final appSearchProvider = NotifierProvider<AppSearchController, String>(
  AppSearchController.new,
);

/// Bumped when the user asks to re-read the installed app list.
///
/// The catalogue itself is cached for the session; this counter is the explicit
/// refresh seam, so opening the drawer again does not pay for a second package
/// scan but pressing Refresh does.
class AppCatalogRevisionController extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() => state++;
}

final appCatalogRevisionProvider =
    NotifierProvider<AppCatalogRevisionController, int>(
      AppCatalogRevisionController.new,
    );

/// How much of the device PaperOS can see at all.
///
/// The drawer branches on this before it asks for a list, so that an
/// unsupported platform gets an explanation rather than a spinner. A platform
/// that reports a restricted, completely empty catalogue is surfaced as
/// [AppCatalogSupport.restricted] so the drawer can explain package visibility
/// instead of claiming nothing is installed.
final appCatalogSupportProvider = Provider<AppCatalogSupport>((Ref ref) {
  final AppCatalogSupport base = ref.watch(appCatalogProvider).support;
  if (base != AppCatalogSupport.full) return base;
  final AppCatalogSnapshot? snapshot = ref
      .watch(appCatalogSnapshotProvider)
      .value;
  if (snapshot != null && snapshot.restricted && snapshot.apps.isEmpty) {
    return AppCatalogSupport.restricted;
  }
  return base;
});

/// One catalogue read, including the platform's incomplete-list signal.
final appCatalogSnapshotProvider = FutureProvider<AppCatalogSnapshot>((
  Ref ref,
) async {
  final int revision = ref.watch(appCatalogRevisionProvider);
  return ref.watch(appCatalogProvider).apps(force: revision > 0);
});

/// Whether the platform admitted that the app list is incomplete.
final appCatalogRestrictedProvider = Provider<bool>((Ref ref) {
  return ref.watch(appCatalogSnapshotProvider).value?.restricted ?? false;
});

/// Every loaded app indexed by package, for favourites and recents.
///
/// The strips must keep working while the drawer search is filtered, so they
/// read the full catalogue rather than [visibleAppsProvider].
final appsByPackageProvider = Provider<Map<String, InstalledApp>>((Ref ref) {
  final List<InstalledApp> apps =
      ref.watch(appCatalogSnapshotProvider).value?.apps ??
      const <InstalledApp>[];
  return <String, InstalledApp>{
    for (final InstalledApp app in apps) app.packageName: app,
  };
});

/// The installed app list, ordered for display.
final installedAppsProvider = FutureProvider<List<InstalledApp>>((
  Ref ref,
) async {
  final AppCatalogSnapshot snapshot = await ref.watch(
    appCatalogSnapshotProvider.future,
  );
  // Select the two fields that actually reorder the catalogue. Watching the
  // whole launcher group would rebuild the list every time a recent is
  // recorded, which makes the drawer flash empty after a launch.
  final bool showSystemApps = ref.watch(
    settingsProvider.select(
      (AppSettings settings) => settings.launcher.showSystemApps,
    ),
  );
  final List<String> favoritePackages = ref.watch(
    settingsProvider.select(
      (AppSettings settings) => settings.launcher.favoritePackages,
    ),
  );
  return AppCatalogQuery.arrange(
    snapshot.apps,
    favoritePackages: favoritePackages,
    showSystemApps: showSystemApps,
  );
});

/// The filtered list the drawer shows.
///
/// Derived synchronously from the cached catalogue so that searching or
/// pinning an app re-orders the existing list instead of flashing a loading
/// state. Only the catalogue read itself is asynchronous.
final visibleAppsProvider = Provider<AsyncValue<List<InstalledApp>>>((Ref ref) {
  final AsyncValue<AppCatalogSnapshot> snapshot = ref.watch(
    appCatalogSnapshotProvider,
  );
  final bool showSystemApps = ref.watch(
    settingsProvider.select(
      (AppSettings settings) => settings.launcher.showSystemApps,
    ),
  );
  final List<String> favoritePackages = ref.watch(
    settingsProvider.select(
      (AppSettings settings) => settings.launcher.favoritePackages,
    ),
  );
  final String query = ref.watch(appSearchProvider);
  return snapshot.whenData((AppCatalogSnapshot data) {
    final List<InstalledApp> ordered = AppCatalogQuery.arrange(
      data.apps,
      favoritePackages: favoritePackages,
      showSystemApps: showSystemApps,
    );
    return AppCatalogQuery.search(ordered, query);
  });
});

/// Pinned apps in pin order, resolved against the loaded catalogue.
///
/// Unknown package names are skipped rather than rendered as blanks: an app can
/// be uninstalled while its pin remains in the settings document.
final favoriteAppsProvider = Provider<List<InstalledApp>>((Ref ref) {
  final LauncherSettings launcher = ref.watch(settingsProvider).launcher;
  // Do not subscribe to the catalogue when there is nothing to resolve. A
  // launcher home screen must not pay for a package scan just because it has a
  // favourites section that is currently empty.
  if (launcher.favoritePackages.isEmpty) return const <InstalledApp>[];
  final Map<String, InstalledApp> byPackage = ref.watch(appsByPackageProvider);
  return <InstalledApp>[
    for (final String packageName in launcher.favoritePackages)
      if (byPackage[packageName] != null) byPackage[packageName]!,
  ];
});

/// Recently launched apps, newest first, or empty when recents are hidden.
final recentAppsProvider = Provider<List<InstalledApp>>((Ref ref) {
  final LauncherSettings launcher = ref.watch(settingsProvider).launcher;
  if (!launcher.showRecents || launcher.recentPackages.isEmpty) {
    return const <InstalledApp>[];
  }
  final Map<String, InstalledApp> byPackage = ref.watch(appsByPackageProvider);
  return <InstalledApp>[
    for (final String packageName in launcher.recentPackages)
      if (byPackage[packageName] != null) byPackage[packageName]!,
  ];
});

/// Whether PaperOS currently holds the Android HOME role.
final homeRoleProvider = FutureProvider<bool>((Ref ref) async {
  return ref.watch(launcherServiceProvider).isHomeApp();
});

/// Launcher mutations and role flows.
///
/// Screens call these; they never touch the platform channel or the settings
/// document directly. Recording a recent after a successful launch keeps the
/// drawer's history honest even when Android refuses to start the app.
class LauncherActions {
  const LauncherActions(this._ref);

  final Ref _ref;

  Future<void> launch(InstalledApp app) async {
    await _ref.read(launcherServiceProvider).launchApp(app);
    await _ref.read(settingsProvider.notifier).recordRecentApp(app.packageName);
  }

  Future<void> toggleFavorite(InstalledApp app) {
    return _ref.read(settingsProvider.notifier).toggleFavorite(app.packageName);
  }

  Future<void> clearRecents() {
    return _ref.read(settingsProvider.notifier).clearRecentApps();
  }

  /// Drops the cached list and asks the platform again.
  void refreshApps() {
    _ref.read(appCatalogProvider).invalidate();
    _ref.read(appCatalogRevisionProvider.notifier).refresh();
  }

  /// Starts the documented Android HOME-role flow and refreshes the status.
  Future<HomeRoleStatus> requestHomeRole() async {
    final HomeRoleStatus status = await _ref
        .read(launcherServiceProvider)
        .requestHomeApp();
    _ref.invalidate(homeRoleProvider);
    return status;
  }

  Future<void> openHomeSettings() {
    return _ref.read(launcherServiceProvider).openHomeSettings();
  }

  /// Re-reads the role after the user returns from system settings.
  void refreshHomeRole() => _ref.invalidate(homeRoleProvider);
}

final launcherActionsProvider = Provider<LauncherActions>(LauncherActions.new);
