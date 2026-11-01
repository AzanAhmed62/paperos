/// How PaperOS should present itself on the current panel.
///
/// This is a user preference, not a guess about the hardware. A person may want
/// the quiet E-Ink Friendly behaviour on an LCD, or full motion on an E-Ink
/// tablet when they are not reading. The profile therefore never relies on a
/// device model name.
enum DisplayProfile {
  /// The normal PaperOS presentation: short page-like transitions and a clock
  /// that keeps itself current.
  standard('standard', 'Standard'),

  /// A deliberately still interface for electrophoretic panels: instant
  /// navigation, no continuously redrawn clock, larger touch targets, stronger
  /// rules and a page-oriented reader.
  eink('eink', 'E-Ink Friendly');

  const DisplayProfile(this.id, this.label);

  /// Stable identifier used in stored settings and backups.
  final String id;

  /// Human-readable name shown in Settings.
  final String label;

  bool get isEink => this == DisplayProfile.eink;

  static DisplayProfile fromId(String? id) {
    for (final DisplayProfile profile in DisplayProfile.values) {
      if (profile.id == id) return profile;
    }
    return DisplayProfile.standard;
  }
}
