import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/display/display_capability_service.dart';
import '../../../core/display/display_policy.dart';
import '../../settings/application/settings_controller.dart';

/// Optional panel-capability lookup. Keeping it behind a provider makes a
/// future documented vendor implementation replaceable in tests and in one
/// place, without letting a widget guess at the hardware.
final displayCapabilityServiceProvider = Provider<DisplayCapabilityService>(
  (Ref ref) => const ConservativeDisplayCapabilityService(),
);

/// The effective rules for the selected display profile.
///
/// This deliberately watches settings: changing the profile takes effect
/// immediately, including the clock cadence and document theme.
final displayPolicyProvider = Provider<DisplayPolicy>((Ref ref) {
  final DisplayCapabilityService service = ref.watch(
    displayCapabilityServiceProvider,
  );
  return DisplayPolicy(
    profile: ref.watch(settingsProvider).display.profile,
    capabilities: service.capabilities(),
  );
});
