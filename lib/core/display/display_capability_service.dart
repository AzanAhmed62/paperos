import 'package:flutter/foundation.dart';

/// Hardware capabilities relevant to a display profile.
///
/// PaperOS only reports capabilities it can actually exercise. There is no
/// generic "E-Ink refresh" API on Android, and undocumented vendor broadcasts
/// are not used. The conservative implementation therefore reports no hardware
/// refresh support; the E-Ink Friendly profile is implemented entirely in
/// software and never pretends a panel was flashed.
@immutable
class DisplayCapabilities {
  const DisplayCapabilities({
    this.isEinkPanel = false,
    this.supportsHardwareRefresh = false,
    this.vendorName,
  });

  /// False when the platform cannot identify the panel. This is deliberately
  /// not inferred from a marketing name or a screen's contrast.
  final bool isEinkPanel;

  /// True only when a documented, testable vendor API is wired up.
  final bool supportsHardwareRefresh;

  /// Vendor whose documented API is in use, if any.
  final String? vendorName;

  static const DisplayCapabilities conservative = DisplayCapabilities();

  String get summary {
    if (supportsHardwareRefresh) {
      return '${vendorName ?? 'Vendor'} hardware refresh API available';
    }
    return 'Software-only E-Ink behaviour; no vendor refresh API detected';
  }
}

/// Resolves optional panel capabilities for [DisplayPolicy].
///
/// The current implementation is intentionally conservative: Android exposes
/// no portable display-refresh API. Keeping this seam means a device-specific
/// implementation can be added only alongside documentation and real hardware
/// validation, without changing the profile policy or the UI.
abstract interface class DisplayCapabilityService {
  DisplayCapabilities capabilities();
}

/// The only implementation shipped in PaperOS 1.2.
class ConservativeDisplayCapabilityService implements DisplayCapabilityService {
  const ConservativeDisplayCapabilityService();

  @override
  DisplayCapabilities capabilities() => DisplayCapabilities.conservative;
}
