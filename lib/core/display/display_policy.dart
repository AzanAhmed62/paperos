import 'package:flutter/widgets.dart';

import 'display_capability_service.dart';
import 'display_profile.dart';

/// Effective presentation rules for the selected [DisplayProfile].
///
/// Every value here is consumed by real widgets. Nothing is a placebo: the
/// router transition, the clock timer, reader pagination, margins, page-turn
/// zones, chrome auto-hide, loading indicators and touch-target sizes all read
/// from this object.
@immutable
class DisplayPolicy {
  const DisplayPolicy({
    this.profile = DisplayProfile.standard,
    this.capabilities = DisplayCapabilities.conservative,
  });

  final DisplayProfile profile;
  final DisplayCapabilities capabilities;

  bool get isEink => profile.isEink;

  /// The E-Ink profile asks for instant navigation. The normal profile keeps
  /// PaperOS' short, page-like transition.
  bool get reduceMotion => isEink;

  Duration get navigationDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 220);

  Duration get chromeAnimationDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 160);

  /// E-Ink panels refresh slowly; a once-a-second rebuild of the home clock is
  /// visible work for a value that only changes every minute. The standard
  /// profile keeps the historic one-second cadence.
  bool get alignClockToMinute => isEink;

  /// A page-oriented reader avoids large scroll regions and partial refreshes.
  bool get forcePagedReader => isEink;

  /// Swipes are full-screen gestures and hard to discover on E-Ink. The
  /// profile uses clearly bounded tap zones while keeping the user's stored
  /// preference untouched underneath.
  bool get forceTapPageTurns => isEink;

  /// Chrome remains visible after it is summoned, so showing a menu does not
  /// start a redraw timer that later removes it.
  bool get autoHideReaderChrome => !isEink;

  /// Larger, clearer controls. Applied through the Material theme and the
  /// shared Paper widgets.
  bool get largeTargets => isEink;

  /// Stronger rules and secondary text; the palettes stay recognisably PaperOS.
  bool get highContrast => isEink;

  /// Selection is drawn with a stronger fill on E-Ink.
  double get selectionOpacity => isEink ? 0.34 : 0.20;

  /// Reader typography is nudged for an electrophoretic panel. The user's
  /// stored values are not modified: the multiplier is applied at render time.
  double get readerFontScale => isEink ? 1.06 : 1;
  double get readerLineHeightDelta => isEink ? 0.06 : 0;
  double get readerMarginScale => isEink ? 1.12 : 1;

  /// Fraction of the reader width that turns back/forward. A wider centre
  /// leaves room for selection without accidentally turning a page.
  double get pageTurnZoneFraction => isEink ? 0.34 : 0.30;

  /// True only when a documented vendor implementation is attached. PaperOS
  /// ships no such implementation in 1.2 and does not emulate one.
  bool get hardwareRefreshAvailable =>
      isEink && capabilities.supportsHardwareRefresh;

  /// A short, honest status line for Settings.
  String get description => isEink
      ? 'Instant navigation, minute-aligned clock, larger controls, stronger '
            'contrast and a page-only reader. No vendor refresh API is used.'
      : 'Short page transitions and the standard reading controls.';

  static const DisplayPolicy standard = DisplayPolicy();
}

/// Provides the active [DisplayPolicy] without making every small shared widget
/// a Riverpod consumer.
class DisplayPolicyScope extends InheritedWidget {
  const DisplayPolicyScope({
    super.key,
    required this.policy,
    required super.child,
  });

  final DisplayPolicy policy;

  static DisplayPolicy of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<DisplayPolicyScope>()
            ?.policy ??
        DisplayPolicy.standard;
  }

  static DisplayPolicy maybeOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<DisplayPolicyScope>()
            ?.policy ??
        DisplayPolicy.standard;
  }

  @override
  bool updateShouldNotify(DisplayPolicyScope oldWidget) =>
      policy != oldWidget.policy;
}
