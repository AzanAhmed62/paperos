import '../../../core/display/display_policy.dart';
import '../../settings/domain/app_settings.dart';

/// Applies display-profile adjustments to the user's stored reading settings.
///
/// The stored values are never mutated. This is a render-time policy so a
/// reader who switches back to Standard finds exactly their previous choices.
ReaderSettings readerSettingsForDisplay(
  ReaderSettings base,
  DisplayPolicy policy,
) {
  if (!policy.isEink) return base;
  return base.copyWith(
    fontSize: (base.fontSize * policy.readerFontScale)
        .clamp(0.85, 1.75)
        .toDouble(),
    lineHeight: (base.lineHeight + policy.readerLineHeightDelta)
        .clamp(1.25, 2.25)
        .toDouble(),
    margin: (base.margin * policy.readerMarginScale)
        .clamp(12.0, 76.0)
        .toDouble(),
    flow: policy.forcePagedReader ? ReaderFlow.paged : base.flow,
    turnMode: policy.forceTapPageTurns ? PageTurnMode.tap : base.turnMode,
  );
}
