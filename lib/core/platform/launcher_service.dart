import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../errors/paper_exception.dart';
import 'installed_app.dart';

/// Everything PaperOS needs from the host platform in order to behave like a
/// launcher.
///
/// The interface exists so that:
///  - widgets never see a `MethodChannel`
///  - the app drawer can be widget-tested on any platform by overriding one
///    provider with a fake
///  - desktop and web builds degrade to a clear "not supported on this
///    platform" state instead of crashing
abstract interface class LauncherService {
  /// Whether the host platform can enumerate and launch apps at all.
  AppCatalogSupport get support;

  /// The launchable applications visible to PaperOS.
  Future<List<InstalledApp>> loadApps();

  /// PNG bytes for a package's launcher icon, or null when it cannot be drawn.
  Future<Uint8List?> loadIcon(String packageName, {int sizePx = 96});

  /// Starts an application. Throws [PaperException] when Android refuses.
  Future<void> launchApp(InstalledApp app);

  /// Whether PaperOS currently holds the HOME role.
  Future<bool> isHomeApp();

  /// Starts the platform flow that lets the user make PaperOS the home app.
  Future<HomeRoleStatus> requestHomeApp();

  /// Opens the system "default home app" settings screen.
  Future<void> openHomeSettings();
}

/// [LauncherService] backed by the Kotlin `AppCatalogChannel`.
class PlatformLauncherService implements LauncherService {
  PlatformLauncherService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'dev.paperos/app_catalog';

  final MethodChannel _channel;

  @override
  AppCatalogSupport get support =>
      defaultTargetPlatform == TargetPlatform.android
      ? AppCatalogSupport.full
      : AppCatalogSupport.unsupported;

  @override
  Future<List<InstalledApp>> loadApps() async {
    if (support == AppCatalogSupport.unsupported) {
      throw const PaperException.platform(
        'Listing installed apps is only available on Android.',
      );
    }
    try {
      final Map<Object?, Object?>? reply = await _channel
          .invokeMapMethod<Object?, Object?>('loadApps');
      final Object? raw = reply?['apps'];
      if (raw is! List) return const <InstalledApp>[];
      return raw
          .whereType<Map<Object?, Object?>>()
          .map(InstalledApp.fromMap)
          .where((InstalledApp app) => app.packageName.isNotEmpty)
          .toList(growable: false);
    } on MissingPluginException {
      throw const PaperException.platform(
        'The Android app catalog is not available in this build.',
      );
    } on PlatformException catch (error) {
      throw PaperException.platform(
        error.message ?? 'PaperOS could not read the list of installed apps.',
        cause: error,
        detail: error.code,
      );
    }
  }

  @override
  Future<Uint8List?> loadIcon(String packageName, {int sizePx = 96}) async {
    if (support == AppCatalogSupport.unsupported) return null;
    try {
      final Uint8List? bytes = await _channel.invokeMethod<Uint8List>(
        'loadIcon',
        <String, Object?>{'packageName': packageName, 'sizePx': sizePx},
      );
      return bytes;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      // A single un-drawable icon must never break the whole drawer.
      return null;
    }
  }

  @override
  Future<void> launchApp(InstalledApp app) async {
    if (support == AppCatalogSupport.unsupported) {
      throw const PaperException.platform(
        'Launching apps is only available on Android.',
      );
    }
    try {
      await _channel.invokeMethod<bool>('launchApp', <String, Object?>{
        'packageName': app.packageName,
        'activityName': app.activityName,
      });
    } on MissingPluginException {
      throw const PaperException.platform(
        'The Android app catalog is not available in this build.',
      );
    } on PlatformException catch (error) {
      throw PaperException.platform(
        error.message ?? 'PaperOS could not open ${app.label}.',
        cause: error,
        detail: error.code,
      );
    }
  }

  @override
  Future<bool> isHomeApp() async {
    try {
      return await _channel.invokeMethod<bool>('isHomeApp') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<HomeRoleStatus> requestHomeApp() async {
    try {
      final Map<Object?, Object?>? reply = await _channel
          .invokeMapMethod<Object?, Object?>('requestHomeApp');
      return HomeRoleStatus(
        isHomeApp: (reply?['isHomeApp'] as bool?) ?? false,
        flow: _flowFromId(reply?['flow'] as String?),
      );
    } on MissingPluginException {
      return HomeRoleStatus.unknown;
    } on PlatformException {
      return HomeRoleStatus.unknown;
    }
  }

  @override
  Future<void> openHomeSettings() async {
    try {
      await _channel.invokeMethod<bool>('openHomeSettings');
    } on MissingPluginException {
      throw const PaperException.platform(
        'The Android home app settings screen could not be opened.',
      );
    } on PlatformException catch (error) {
      throw PaperException.platform(
        error.message ?? 'The home app settings screen could not be opened.',
        cause: error,
      );
    }
  }

  static HomeRoleFlow _flowFromId(String? id) {
    switch (id) {
      case 'role_request':
        return HomeRoleFlow.roleRequest;
      case 'settings':
        return HomeRoleFlow.settings;
      case 'already':
        return HomeRoleFlow.already;
      default:
        return HomeRoleFlow.unavailable;
    }
  }
}
