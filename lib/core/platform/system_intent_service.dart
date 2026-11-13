import 'dart:async';

import 'package:flutter/services.dart';

/// Why Android brought PaperOS to the foreground.
///
/// A VIEW intent is a document request and is owned by the file-browser
/// channel. HOME and LAUNCHER intents are launcher traffic: they must reset the
/// visible hierarchy to Paper Home rather than resume the last reader page.
enum SystemIntentKind {
  home('home'),
  launcher('launcher'),
  view('view');

  const SystemIntentKind(this.id);

  final String id;

  static SystemIntentKind? fromId(String? id) {
    for (final SystemIntentKind kind in SystemIntentKind.values) {
      if (kind.id == id) return kind;
    }
    return null;
  }
}

/// The platform seam for launcher intents.
///
/// Kept separate from `FileBrowserService` because the two intents have
/// different owners: VIEW imports a document, HOME resets navigation. Mixing
/// them in one channel is how a launcher ends up opening a stale reader page
/// every time the user presses Home.
abstract interface class SystemIntentService {
  /// Claims the intent that started the process, if it has not been claimed.
  Future<SystemIntentKind?> claimInitialIntent();

  /// Collects an intent stashed while Dart was not listening.
  Future<SystemIntentKind?> takePending();

  /// Intents delivered while the app is already running.
  Stream<SystemIntentKind> get intents;

  void dispose();
}

/// [SystemIntentService] backed by the Kotlin `SystemIntentChannel`.
class PlatformSystemIntentService implements SystemIntentService {
  PlatformSystemIntentService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const String channelName = 'dev.paperos/system_intent';

  final MethodChannel _channel;
  final StreamController<SystemIntentKind> _controller =
      StreamController<SystemIntentKind>.broadcast();

  @override
  Stream<SystemIntentKind> get intents => _controller.stream;

  @override
  Future<SystemIntentKind?> claimInitialIntent() => _invoke('ready');

  @override
  Future<SystemIntentKind?> takePending() => _invoke('takePending');

  Future<SystemIntentKind?> _invoke(String method) async {
    try {
      final String? kind = await _channel.invokeMethod<String>(method);
      return SystemIntentKind.fromId(kind);
    } on MissingPluginException {
      // Desktop, web, or a widget test: there is no launcher intent.
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'systemIntent') return null;
    final SystemIntentKind? kind = SystemIntentKind.fromId(
      call.arguments as String?,
    );
    if (kind != null && !_controller.isClosed) _controller.add(kind);
    return null;
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _controller.close();
  }
}
