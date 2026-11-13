import 'package:flutter/foundation.dart';

/// One launchable application on the device.
@immutable
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.activityName,
    required this.label,
    required this.isSystem,
  });

  final String packageName;

  /// Fully qualified activity class. Kept so that launching targets exactly the
  /// component the launcher declared, instead of re-resolving a launch intent
  /// that a work-profile or dual-SIM setup may resolve differently.
  final String activityName;

  final String label;
  final bool isSystem;

  factory InstalledApp.fromMap(Map<Object?, Object?> map) {
    return InstalledApp(
      packageName: (map['packageName'] as String?) ?? '',
      activityName: (map['activityName'] as String?) ?? '',
      label: (map['label'] as String?) ?? '',
      isSystem: (map['isSystem'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InstalledApp && other.packageName == packageName;

  @override
  int get hashCode => packageName.hashCode;
}

/// The result of one catalogue read.
///
/// [restricted] is the platform's own admission that the list is almost
/// certainly incomplete — on Android 11+ that means package visibility blocked
/// the query. Keeping the flag beside the list lets the drawer explain the
/// limit instead of showing a convincing but false "no apps installed" screen.
@immutable
class AppCatalogSnapshot {
  const AppCatalogSnapshot({required this.apps, this.restricted = false});

  static const AppCatalogSnapshot empty = AppCatalogSnapshot(
    apps: <InstalledApp>[],
  );

  final List<InstalledApp> apps;
  final bool restricted;
}

/// The result of asking Android to make PaperOS the home app.
enum HomeRoleFlow {
  /// The system role dialog was opened. The user still has to confirm.
  roleRequest,

  /// Pre-Android 10: the home-app picker in Settings was opened.
  settings,

  /// PaperOS already holds the role.
  already,

  /// This device will not allow it.
  unavailable,
}

@immutable
class HomeRoleStatus {
  const HomeRoleStatus({required this.isHomeApp, required this.flow});

  static const HomeRoleStatus unknown = HomeRoleStatus(
    isHomeApp: false,
    flow: HomeRoleFlow.unavailable,
  );

  final bool isHomeApp;
  final HomeRoleFlow flow;
}

/// How much PaperOS can see of the installed app list.
enum AppCatalogSupport {
  /// The platform is Android and the channel answered.
  full,

  /// The platform channel is not available (desktop, web, or an Android build
  /// without the channel). The drawer shows an honest empty state.
  unsupported,

  /// The platform answered but the list came back suspiciously small, which on
  /// Android 11+ usually means the `<queries>` manifest entry is missing.
  restricted,
}
