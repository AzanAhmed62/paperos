import 'dart:typed_data';

import 'package:paperos/core/errors/paper_exception.dart';
import 'package:paperos/core/platform/installed_app.dart';
import 'package:paperos/core/platform/launcher_service.dart';

/// A launcher seam that answers deterministically, so drawer and Home tests do
/// not need an Android device or a mocked method channel.
class FakeLauncherService implements LauncherService {
  FakeLauncherService({
    this.apps = const <InstalledApp>[],
    this.restricted = false,
    this.home = false,
    this.requestFlow = HomeRoleFlow.already,
    this.failLaunch = false,
  });

  final List<InstalledApp> apps;
  final bool restricted;
  bool home;
  HomeRoleFlow requestFlow;
  bool failLaunch;

  int loadCount = 0;
  int iconCount = 0;
  int openSettingsCount = 0;
  final List<InstalledApp> launched = <InstalledApp>[];

  @override
  AppCatalogSupport get support => AppCatalogSupport.full;

  @override
  Future<AppCatalogSnapshot> loadApps() async {
    loadCount++;
    return AppCatalogSnapshot(apps: apps, restricted: restricted);
  }

  @override
  Future<Uint8List?> loadIcon(String packageName, {int sizePx = 96}) async {
    iconCount++;
    return null;
  }

  @override
  Future<void> launchApp(InstalledApp app) async {
    if (failLaunch) {
      throw const PaperException.platform('Android refused to launch the app.');
    }
    launched.add(app);
  }

  @override
  Future<bool> isHomeApp() async => home;

  @override
  Future<HomeRoleStatus> requestHomeApp() async {
    if (requestFlow == HomeRoleFlow.roleRequest) home = true;
    return HomeRoleStatus(isHomeApp: home, flow: requestFlow);
  }

  @override
  Future<void> openHomeSettings() async {
    openSettingsCount++;
  }
}

InstalledApp fakeApp(
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
