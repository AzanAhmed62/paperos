import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/theme/paper_palette.dart';

double _contrast(Color a, Color b) {
  final double lighter = a.computeLuminance() > b.computeLuminance()
      ? a.computeLuminance()
      : b.computeLuminance();
  final double darker = a.computeLuminance() > b.computeLuminance()
      ? b.computeLuminance()
      : a.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('PaperPalette contrast', () {
    for (final PaperStyle style in PaperStyle.values) {
      test('${style.id} keeps reading text legible on paper', () {
        final PaperPalette palette = PaperPalette.of(style);

        expect(_contrast(palette.ink, palette.canvas), greaterThanOrEqualTo(7));
        expect(
          _contrast(palette.inkMuted, palette.canvas),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(palette.inkFaint, palette.canvas),
          greaterThanOrEqualTo(3),
        );
        expect(
          _contrast(palette.inverseInk, palette.inverseCanvas),
          greaterThanOrEqualTo(7),
        );
      });

      test('${style.id} keeps highlight and note text readable', () {
        final PaperPalette palette = PaperPalette.of(style);

        expect(
          _contrast(palette.ink, palette.highlight),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(palette.ink, palette.noteFill),
          greaterThanOrEqualTo(4.5),
        );
        // A highlight must be distinguishable from the page, not merely a
        // different colour token that happens to be the same value.
        expect(_contrast(palette.highlight, palette.canvas), greaterThan(1.05));
        expect(_contrast(palette.noteFill, palette.canvas), greaterThan(1.03));
        expect(palette.highlight, isNot(palette.rule));
        expect(palette.noteFill, isNot(palette.rule));
      });

      test('${style.id} high-contrast variant strengthens secondary ink', () {
        final PaperPalette palette = PaperPalette.of(style).highContrast();

        expect(_contrast(palette.ink, palette.canvas), greaterThanOrEqualTo(7));
        expect(
          _contrast(palette.inkFaint, palette.canvas),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(palette.ink, palette.highlight),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    test('Ink is charcoal and off-white, not a pure black inversion', () {
      const PaperPalette ink = PaperPalette.paperInk;

      expect(ink.canvas, isNot(const Color(0xFF000000)));
      expect(ink.ink, isNot(const Color(0xFFFFFFFF)));
      expect(ink.isDark, isTrue);
    });
  });
}
