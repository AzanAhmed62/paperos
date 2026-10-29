import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../features/files/application/external_open_controller.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/domain/app_settings.dart';
import '../theme/paper_theme.dart';
import '../theme/paper_typography.dart';
import 'router.dart';

/// The PaperOS root.
///
/// Stateful only so the "Open with PaperOS" watcher can be started exactly once
/// and survive for the life of the app; everything visual still rebuilds through
/// Riverpod when settings change.
class PaperApp extends ConsumerStatefulWidget {
  const PaperApp({super.key});

  @override
  ConsumerState<PaperApp> createState() => _PaperAppState();
}

class _PaperAppState extends ConsumerState<PaperApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Reading (not watching) builds the singleton for the app's lifetime. It
    // has no visual output; a document it accepts is opened through the router.
    ref.read(externalOpenControllerProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A VIEW intent that arrived while backgrounded may only be visible on
    // resume; re-draining is cheap and idempotent (the native side clears it).
    if (state == AppLifecycleState.resumed) {
      ref.read(externalOpenControllerProvider.notifier).drainPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(settingsProvider);

    return MaterialApp.router(
      title: PaperConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: PaperTheme.build(
        style: settings.appearance.style,
        typeOptions: PaperTypeOptions(
          scale: settings.appearance.textScale,
          serifReading: settings.appearance.serifReading,
        ),
      ),
      routerConfig: appRouter,
      builder: (BuildContext context, Widget? child) {
        // The system font scale is deliberately not multiplied in here.
        // PaperOS applies exactly one scale of its own, from Settings: the
        // reading surface is paginated against a measured size, and two
        // independent scales would paginate it wrongly.
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
