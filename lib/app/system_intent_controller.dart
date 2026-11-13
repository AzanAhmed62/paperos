import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/system_intent_service.dart';
import '../features/files/application/external_open_controller.dart';
import '../features/files/application/files_providers.dart';
import '../features/launcher/application/launcher_providers.dart';
import 'providers.dart';
import 'router.dart';

/// Turns Android launcher intents into PaperOS navigation.
///
/// Android is allowed to keep one task alive for days and deliver a new intent
/// into it. Without this controller, pressing Home while the reader is open
/// would simply show the reader again: the activity is already running, so a
/// cold-start-only reset never happens. HOME and LAUNCHER therefore reset the
/// hierarchy to Paper Home; VIEW is left to the document-import controller,
/// which owns the one-shot content grant.
class SystemIntentController extends Notifier<int> {
  StreamSubscription<SystemIntentKind>? _subscription;

  @override
  int build() {
    final SystemIntentService service = ref.read(systemIntentServiceProvider);
    _subscription = service.intents.listen(_handle);
    ref.onDispose(() => _subscription?.cancel());
    // The intent that started the process is delivered through
    // Activity.getIntent, not onNewIntent, so ask for it explicitly.
    scheduleMicrotask(drainInitial);
    return 0;
  }

  /// Claims the cold-start intent, if the platform has one.
  Future<void> drainInitial() async {
    final SystemIntentKind? kind = await ref
        .read(systemIntentServiceProvider)
        .claimInitialIntent();
    if (kind != null) _handle(kind);
  }

  /// Collects an intent stashed while the engine was paused.
  Future<void> drainPending() async {
    final SystemIntentKind? kind = await ref
        .read(systemIntentServiceProvider)
        .takePending();
    if (kind != null) _handle(kind);
  }

  void _handle(SystemIntentKind kind) {
    switch (kind) {
      case SystemIntentKind.home:
      case SystemIntentKind.launcher:
        _resetToHome();
      case SystemIntentKind.view:
        // FileBrowserChannel already stashed the document; the external-open
        // controller imports it and pushes the reader. Never reset first, or a
        // cold-start VIEW would race its own navigation.
        ref.read(externalOpenControllerProvider.notifier).drainPending();
    }
  }

  void _resetToHome() {
    ref.read(filesBrowseProvider.notifier).reset();
    ref.read(appSearchProvider.notifier).clear();
    ref.read(appRouterProvider).go(Routes.home);
    state = state + 1;
  }
}

final systemIntentControllerProvider =
    NotifierProvider<SystemIntentController, int>(SystemIntentController.new);
