import 'package:flutter/widgets.dart';

/// The visual identity of PaperOS.
///
/// PaperOS deliberately has no accent colour. Every surface is built from
/// ink (text and lines) on paper (background), plus exactly one inversion used
/// for selection. Keeping the palette this small is what makes the product
/// read as "paper" rather than as a normal colourful Android app.
enum PaperStyle {
  /// Pure white paper, black ink. Maximum contrast.
  white('white', 'White'),

  /// A warm, slightly yellowed paper tone for long reading sessions.
  warm('warm', 'Warm'),

  /// Inverted: black paper, light ink. The dark-room reading mode.
  ink('ink', 'Ink');

  const PaperStyle(this.id, this.label);

  /// Stable identifier used for persistence. Never localise these values.
  final String id;

  /// Human readable name shown in Settings.
  final String label;

  static PaperStyle fromId(String? id) {
    for (final style in PaperStyle.values) {
      if (style.id == id) return style;
    }
    return PaperStyle.white;
  }
}

/// Resolved colour roles for a [PaperStyle].
///
/// A `PaperPalette` is a plain value object: it is created once per theme and
/// read synchronously by widgets. It is intentionally not a Flutter
/// `ColorScheme` because PaperOS does not want the Material colour roles to be
/// reachable from feature code — that is how apps slowly become colourful.
@immutable
class PaperPalette {
  const PaperPalette({
    required this.style,
    required this.canvas,
    required this.raised,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.rule,
    required this.ruleStrong,
    required this.inverseCanvas,
    required this.inverseInk,
    required this.highlight,
    required this.noteFill,
  });

  final PaperStyle style;

  /// Page background.
  final Color canvas;

  /// Background for the few elements that need to sit "on" the page, such as
  /// the reader control bar. Deliberately identical to [canvas] in most
  /// styles so the UI never looks like floating cards.
  final Color raised;

  /// Primary text.
  final Color ink;

  /// Secondary text: metadata, helper copy.
  final Color inkMuted;

  /// Tertiary text: section labels, disabled state, placeholders.
  final Color inkFaint;

  /// Hairline dividers.
  final Color rule;

  /// Slightly stronger dividers, used to close sections.
  final Color ruleStrong;

  /// Inverted fill, used for the currently selected tab or a pressed state.
  final Color inverseCanvas;

  /// Text drawn on [inverseCanvas].
  final Color inverseInk;

  /// Reader highlight fill. Deliberately a warm, low-chroma wash rather than a
  /// saturated marker colour; in Ink it must remain visible without glowing.
  final Color highlight;

  /// Reader annotation-note fill, one step quieter than [highlight].
  final Color noteFill;

  bool get isDark => style == PaperStyle.ink;

  static const PaperPalette paperWhite = PaperPalette(
    style: PaperStyle.white,
    canvas: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    ink: Color(0xFF101010),
    inkMuted: Color(0xFF5A5A5A),
    inkFaint: Color(0xFF8C8C8C),
    rule: Color(0xFFE6E6E6),
    ruleStrong: Color(0xFF101010),
    inverseCanvas: Color(0xFF101010),
    inverseInk: Color(0xFFFFFFFF),
    highlight: Color(0xFFF1E7CC),
    noteFill: Color(0xFFE8DEC7),
  );

  static const PaperPalette paperWarm = PaperPalette(
    style: PaperStyle.warm,
    canvas: Color(0xFFF4EFE4),
    raised: Color(0xFFFAF6EE),
    ink: Color(0xFF1A1713),
    inkMuted: Color(0xFF5B5347),
    inkFaint: Color(0xFF8E8577),
    rule: Color(0xFFE0D7C6),
    ruleStrong: Color(0xFF1A1713),
    inverseCanvas: Color(0xFF1A1713),
    inverseInk: Color(0xFFF4EFE4),
    highlight: Color(0xFFEADCB9),
    noteFill: Color(0xFFDFD1B0),
  );

  static const PaperPalette paperInk = PaperPalette(
    style: PaperStyle.ink,
    // A neutral charcoal page, not pure black: long sessions keep a sense of
    // paper, and the off-white ink stays softer than a pure-white glare.
    canvas: Color(0xFF121211),
    raised: Color(0xFF191917),
    ink: Color(0xFFE8E4DA),
    inkMuted: Color(0xFFB3AFA6),
    inkFaint: Color(0xFF878279),
    rule: Color(0xFF2E2D29),
    ruleStrong: Color(0xFF5A5650),
    inverseCanvas: Color(0xFFE8E4DA),
    inverseInk: Color(0xFF121211),
    highlight: Color(0xFF40392C),
    noteFill: Color(0xFF332F27),
  );

  static const Map<PaperStyle, PaperPalette> byStyle = {
    PaperStyle.white: paperWhite,
    PaperStyle.warm: paperWarm,
    PaperStyle.ink: paperInk,
  };

  static PaperPalette of(PaperStyle style) => byStyle[style]!;

  /// A stronger variant of this palette for the E-Ink Friendly profile.
  ///
  /// The paper and ink identity is preserved; only secondary text and hairlines
  /// become darker so they survive a panel with fewer grey levels. Text
  /// selection uses an ink fill whose opacity is raised by DisplayPolicy.
  PaperPalette highContrast() {
    return switch (style) {
      PaperStyle.white => const PaperPalette(
        style: PaperStyle.white,
        canvas: Color(0xFFFFFFFF),
        raised: Color(0xFFFFFFFF),
        ink: Color(0xFF000000),
        inkMuted: Color(0xFF303030),
        inkFaint: Color(0xFF565656),
        rule: Color(0xFFB4B4B4),
        ruleStrong: Color(0xFF000000),
        inverseCanvas: Color(0xFF000000),
        inverseInk: Color(0xFFFFFFFF),
        highlight: Color(0xFFF2E2B4),
        noteFill: Color(0xFFE5D3A4),
      ),
      PaperStyle.warm => const PaperPalette(
        style: PaperStyle.warm,
        canvas: Color(0xFFF4EFE4),
        raised: Color(0xFFFAF6EE),
        ink: Color(0xFF000000),
        inkMuted: Color(0xFF3B342A),
        inkFaint: Color(0xFF62594C),
        rule: Color(0xFFBBAF9A),
        ruleStrong: Color(0xFF000000),
        inverseCanvas: Color(0xFF17130F),
        inverseInk: Color(0xFFF4EFE4),
        highlight: Color(0xFFEAD9AE),
        noteFill: Color(0xFFDCC998),
      ),
      PaperStyle.ink => const PaperPalette(
        style: PaperStyle.ink,
        canvas: Color(0xFF000000),
        raised: Color(0xFF0C0C0B),
        ink: Color(0xFFFFFFFF),
        inkMuted: Color(0xFFD8D4CB),
        inkFaint: Color(0xFFB0ABA2),
        rule: Color(0xFF5E5A54),
        ruleStrong: Color(0xFFC8C3B9),
        inverseCanvas: Color(0xFFFFFFFF),
        inverseInk: Color(0xFF000000),
        highlight: Color(0xFF4A4334),
        noteFill: Color(0xFF3D372C),
      ),
    };
  }
}
