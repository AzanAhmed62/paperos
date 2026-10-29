/// Spacing scale.
///
/// PaperOS uses an 4pt base grid. Values are named by role, not by number, so
/// that a change in rhythm is a one-line change here instead of a search across
/// every screen.
abstract final class PaperSpace {
  /// Hairline gap, e.g. between an icon and its label.
  static const double xxs = 2;

  /// Inside a single control.
  static const double xs = 4;

  /// Between tightly related elements.
  static const double sm = 8;

  /// Default gap between related blocks.
  static const double md = 12;

  /// Standard list padding / gap between list rows.
  static const double lg = 16;

  /// Between sections.
  static const double xl = 24;

  /// Above a screen title.
  static const double xxl = 32;

  /// Above the first block of a screen.
  static const double xxxl = 48;

  /// Horizontal page margin. Screens use this instead of padding themselves.
  static const double gutter = 22;
}
