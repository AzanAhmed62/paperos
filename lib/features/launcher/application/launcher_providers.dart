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

/// How much of the device PaperOS can see at all.
///
/// The drawer branches on this before it asks for a list, so that an
/// unsupported platform gets an explanation rather than a spinner.
final appCatalogSupportProvider = Provider<AppCatalogSupport>((Ref ref) {
  return ref.watch(appCatalogProvider).support;
});

/// The installed app list, ordered for display.
final installedAppsProvider = FutureProvider<List<InstalledApp>>((
  Ref ref,
) async {
  final List<InstalledApp> apps = await ref.watch(appCatalogProvider).apps();
  final LauncherSettings launcher = ref.watch(settingsProvider).launcher;
  return AppCatalogQuery.arrange(
    apps,
    favoritePackages: launcher.favoritePackages,
    showSystemApps: launcher.showSystemApps,
  );
});

/// The filtered list the drawer shows.
final visibleAppsProvider = FutureProvider<List<InstalledApp>>((Ref ref) async {
  final List<InstalledApp> ordered = await ref.watch(
    installedAppsProvider.future,
  );
  return AppCatalogQuery.search(ordered, ref.watch(appSearchProvider));
});

/// Whether PaperOS currently holds the Android HOME role.
final homeRoleProvider = FutureProvider<bool>((Ref ref) async {
  return ref.watch(launcherServiceProvider).isHomeApp();
});
