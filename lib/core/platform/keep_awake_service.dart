import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls whether the platform keeps the display awake.
///
/// An interface rather than a bare channel so the reader can be widget-tested
/// with a fake, and so a non-Android build silently does nothing instead of
/// throwing when the reader opens.
abstract interface class KeepAwakeService {
  /// Whether the host platform can hold the screen on at all.
  bool get isSupported;

  /// Keeps the screen on until [disable] is called.
  Future<void> enable();

  /// Releases the wake lock. Safe to call when it was never held.
  Future<void> disable();
}

/// [KeepAwakeService] backed by the Kotlin `KeepScreenOnChannel`, which sets
/// `WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON` on the current window.
///
/// This uses the window flag rather than a `WakeLock`. A window flag needs no
/// permission, is scoped to PaperOS' own window, and is released automatically
/// when the window is destroyed — which is exactly the guarantee a reading app
/// wants and a partial `WAKE_LOCK` does not give.
class PlatformKeepAwakeService implements KeepAwakeService {
  PlatformKeepAwakeService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'dev.paperos/keep_screen_on';

  final MethodChannel _channel;

  @override
  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> enable() => _set(true);

  @override
  Future<void> disable() => _set(false);

  Future<void> _set(bool enabled) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('setKeepScreenOn', <String, Object?>{
        'enabled': enabled,
      });
    } on MissingPluginException {
      // A build without the native channel simply cannot hold the screen on;
      // that is not worth interrupting reading for.
    } on PlatformException {
      // Same reasoning: failing to keep the screen on is never fatal.
    }
  }
}
