
import 'package:flutter/material.dart';

import 'paper_palette.dart';

/// Font family used for the reading surface and display numerals.
///
/// Bundled so that reading typography is identical on every platform and
/// available with no network access.
const String kPaperSerifFamily = 'PaperSerif';

/// Typography options that come from user settings.
@immutable
class PaperTypeOptions {
  const PaperTypeOptions({
    this.scale = 1,
    this.serifReading = true,
  });

  /// Multiplier applied to every size. Exposed in Settings as "Text size".
  final double scale;

  /// Whether the reading surface uses the bundled serif face.
  final bool serifReading;

  PaperTypeOptions copyWith({double? scale, bool? serifReading}) {
    return PaperTypeOptions(
      scale: scale ?? this.scale,
      serifReading: serifReading ?? this.serifReading,
    );
  }
}

/// The complete, semantic type scale of PaperOS.
///
/// Feature code must use these named styles. Raw `TextStyle(fontSize: 17)`
/// calls in a screen are a code smell: they break text scaling, they break the
/// serif reading option, and they make the rhythm impossible to tune later.
@immutable
class PaperTypography extends ThemeExtension<PaperTypography> {
  PaperTypography({required this.palette, required this.options})
    : _styles = _build(palette, options);

  final PaperPalette palette;
  final PaperTypeOptions options;

  final Map<String, TextStyle> _styles;

  // --- Display ------------------------------------------------------------

  /// The clock on Paper Home. Tabular figures so the width never changes.
  TextStyle get clock => _styles['clock']!;

  /// Day and date line under the clock.
  TextStyle get date => _styles['date']!;

  // --- Structure ----------------------------------------------------------

  /// Screen titles. Large, quiet, bold-ish.
  TextStyle get screenTitle => _styles['screenTitle']!;

  /// Titles for pushed screens and sheets.
  TextStyle get screenTitleSmall => _styles['screenTitleSmall']!;

  /// Card/section headline.
  TextStyle get heading => _styles['heading']!;

  /// Small uppercase tracked label that opens every section.
  TextStyle get sectionLabel => _styles['sectionLabel']!;

  // --- Content ------------------------------------------------------------

  TextStyle get body => _styles['body']!;
  TextStyle get bodyStrong => _styles['bodyStrong']!;
  TextStyle get bodyQuiet => _styles['bodyQuiet']!;

  /// Primary list row title.
  TextStyle get listTitle => _styles['listTitle']!;

  /// Secondary line under a list row title.
  TextStyle get listSubtitle => _styles['listSubtitle']!;

  /// Metadata such as "PDF · 24 pages · 2 days ago".
  TextStyle get meta => _styles['meta']!;

  /// Tertiary metadata and empty-state copy.
  TextStyle get caption => _styles['caption']!;

  /// Reading progress percentage. Tabular.
  TextStyle get percent => _styles['percent']!;

  /// Bottom navigation labels.
  TextStyle get navLabel => _styles['navLabel']!;

  // --- Controls -----------------------------------------------------------

  /// Buttons and tappable labels.
  TextStyle get action => _styles['action']!;

  /// Text field contents. 16px minimum so iOS/Android never zoom.
  TextStyle get input => _styles['input']!;

  /// Field labels.
  TextStyle get fieldLabel => _styles['fieldLabel']!;

  // --- Reading ------------------------------------------------------------

  /// Body of the reading surface. Serif, generous line height, justified
  /// measure kept short by the reader's own padding.
  TextStyle get readingBody => _styles['readingBody']!;

  /// First page of a text document / document title in the reader.
  TextStyle get readingTitle => _styles['readingTitle']!;

  /// Chapter-ish label in the reader.
  TextStyle get readingHeading => _styles['readingHeading']!;

  static Map<String, TextStyle> _build(
    PaperPalette palette,
    PaperTypeOptions options,
  ) {
    final double s = options.scale;
    final Color ink = palette.ink;
    final Color muted = palette.inkMuted;
    final Color faint = palette.inkFaint;
    final String? readingFamily = options.serifReading
        ? kPaperSerifFamily
        : null;

    TextStyle ui({
      required double size,
      FontWeight weight = FontWeight.w400,
      double height = 1.35,
      double spacing = 0,
      Color? color,
      FontStyle? fontStyle,
    }) {
      return TextStyle(
        fontSize: size * s,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color ?? ink,
        fontStyle: fontStyle,
        // Keep the app off the synthetic-bold path; real weights are declared.
        leadingDistribution: TextLeadingDistribution.even,
      );
    }

    return <String, TextStyle>{
      'clock': ui(
        size: 72,
        weight: FontWeight.w300,
        height: 1.0,
        spacing: -2,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      'date': ui(size: 15, color: muted, spacing: 0.2),
      'screenTitle': ui(size: 27, weight: FontWeight.w700, height: 1.15),
      'screenTitleSmall': ui(size: 20, weight: FontWeight.w700, height: 1.2),
      'heading': ui(size: 17, weight: FontWeight.w600, height: 1.3),
      'sectionLabel': ui(
        size: 11,
        weight: FontWeight.w700,
        height: 1.2,
        spacing: 1.9,
        color: faint,
      ),
      'body': ui(size: 15, height: 1.45),
      'bodyStrong': ui(size: 15, weight: FontWeight.w600, height: 1.4),
      'bodyQuiet': ui(size: 15, height: 1.45, color: muted),
      'listTitle': ui(size: 15.5, weight: FontWeight.w600, height: 1.25),
      'listSubtitle': ui(size: 13, height: 1.35, color: muted),
      'meta': ui(size: 12.5, height: 1.3, color: muted),
      'caption': ui(size: 11.5, height: 1.35, color: faint),
      'percent': ui(
        size: 13,
        weight: FontWeight.w600,
        height: 1.2,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      'navLabel': ui(
        size: 10.5,
        weight: FontWeight.w600,
        height: 1.1,
        spacing: 0.9,
      ),
      'action': ui(size: 14, weight: FontWeight.w600, height: 1.2, spacing: 0.4),
      'input': ui(size: 16, height: 1.4),
      'fieldLabel': ui(size: 12.5, weight: FontWeight.w600, color: muted),
      'readingBody': ui(
        size: 18.5,
        height: 1.62,
        spacing: 0.1,
      ).copyWith(fontFamily: readingFamily),
      'readingTitle': ui(
        size: 26,
        weight: FontWeight.w700,
        height: 1.25,
      ).copyWith(fontFamily: readingFamily),
      'readingHeading': ui(
        size: 19,
        weight: FontWeight.w700,
        height: 1.35,
      ).copyWith(fontFamily: readingFamily),
    };
  }

  @override
  PaperTypography copyWith({PaperPalette? palette, PaperTypeOptions? options}) {
    return PaperTypography(
      palette: palette ?? this.palette,
      options: options ?? this.options,
    );
  }

  @override
  PaperTypography lerp(covariant PaperTypography? other, double t) {
    if (other == null) return this;
    // Text styles are not meaningfully interpolable for a product that never
    // animates between themes; switching themes is instant by design.
    return t < 0.5 ? this : other;
  }

  static PaperTypography of(BuildContext context) {
    return Theme.of(context).extension<PaperTypography>()!;
  }
}
