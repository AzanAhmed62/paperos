import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../core/display/display_policy.dart';
import '../features/display/application/display_providers.dart';
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
    final DisplayPolicy display = ref.watch(displayPolicyProvider);

    return MaterialApp.router(
      title: PaperConfig.appName,
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: display.navigationDuration,
      themeAnimationCurve: Curves.linear,
      theme: PaperTheme.build(
        style: settings.appearance.style,
        typeOptions: PaperTypeOptions(
          scale: settings.appearance.textScale,
          serifReading: settings.appearance.serifReading,
        ),
        einkFriendly: display.isEink,
      ),
      routerConfig: appRouter,
      builder: (BuildContext context, Widget? child) {
        // The system font scale is deliberately not multiplied in here.
        // PaperOS applies exactly one scale of its own, from Settings: the
        // reading surface is paginated against a measured size, and two
        // independent scales would paginate it wrongly.
        //
        // The display policy is exposed both as an inherited value (for small
        // shared widgets) and as MediaQuery.disableAnimations (for framework
        // routes and selection overlays). That makes "instant" apply to pushes,
        // sheets and dialogs, not just the screens PaperOS draws itself.
        final MediaQueryData media = MediaQuery.of(context);
        Widget content = MediaQuery(
          data: media.copyWith(
            disableAnimations: display.reduceMotion,
            highContrast: display.highContrast || media.highContrast,
          ),
          child: DisplayPolicyScope(
            policy: display,
            child: child ?? const SizedBox.shrink(),
          ),
        );
        return content;
      },
    );
  }
}
