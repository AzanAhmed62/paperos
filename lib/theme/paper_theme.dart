import 'package:flutter/material.dart';

import 'paper_palette.dart';
import 'paper_space.dart';
import 'paper_typography.dart';

/// Builds the [ThemeData] for a given [PaperStyle].
///
/// The Material theme exists mostly so that framework widgets (text fields,
/// dialogs, scrollbars) do not look foreign. Everything PaperOS draws itself
/// reads from the [PaperPalette] and [PaperTypography] extension instead of
/// from `Theme.of(context).colorScheme`.
abstract final class PaperTheme {
  static ThemeData build({
    required PaperStyle style,
    PaperTypeOptions typeOptions = const PaperTypeOptions(),
  }) {
    final PaperPalette palette = PaperPalette.of(style);

    final TextTheme textTheme = TextTheme(
      bodyLarge: TextStyle(fontFamily: null, fontSize: 15, color: palette.ink),
      bodyMedium: TextStyle(fontSize: 13, color: palette.inkMuted),
      labelSmall: TextStyle(fontSize: 11.5, color: palette.inkFaint),
    );

    final ColorScheme colorScheme = ColorScheme(
      brightness: palette.isDark ? Brightness.dark : Brightness.light,
      primary: palette.ink,
      onPrimary: palette.inverseInk,
      secondary: palette.inkMuted,
      onSecondary: palette.canvas,
      error: palette.ink,
      onError: palette.inverseInk,
      surface: palette.canvas,
      onSurface: palette.ink,
      surfaceContainerHighest: palette.raised,
      onSurfaceVariant: palette.inkMuted,
      outline: palette.rule,
      outlineVariant: palette.rule,
      shadow: palette.rule,
      scrim: palette.ink,
      inverseSurface: palette.inverseCanvas,
      onInverseSurface: palette.inverseInk,
      inversePrimary: palette.inverseCanvas,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: palette.isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.canvas,
      fontFamily: null,
      textTheme: textTheme,
      // PaperOS does not use ripples. On an e-ink panel a ripple is a smear,
      // and on a normal panel it adds motion noise for no informational gain.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      dividerTheme: DividerThemeData(
        color: palette.rule,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: palette.ink, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.canvas,
        foregroundColor: palette.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: palette.ink,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(),
        showDragHandle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: palette.ink,
        ),
        contentTextStyle: TextStyle(fontSize: 14.5, color: palette.inkMuted),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.ink,
        selectionColor: palette.rule,
        selectionHandleColor: palette.ink,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.ink,
          backgroundColor: Colors.transparent,
          overlayColor: Colors.transparent,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: PaperSpace.sm),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.ink,
          overlayColor: Colors.transparent,
          minimumSize: const Size(44, 44),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: PaperSpace.md),
        hintStyle: TextStyle(color: palette.inkFaint, fontSize: 16),
        labelStyle: TextStyle(color: palette.inkMuted, fontSize: 13),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.transparent),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.transparent),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.transparent),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.ink,
        textColor: palette.ink,
        titleTextStyle: TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
          color: palette.ink,
        ),
        subtitleTextStyle: TextStyle(fontSize: 13, color: palette.inkMuted),
        shape: const RoundedRectangleBorder(),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.ink;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(palette.inverseInk),
        side: BorderSide(color: palette.inkFaint, width: 1.2),
        shape: const RoundedRectangleBorder(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? palette.inverseInk
              : palette.inkFaint;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.ink;
          return Colors.transparent;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.ink;
          return palette.inkFaint;
        }),
        trackOutlineWidth: const WidgetStatePropertyAll(1.2),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.ink,
        inactiveTrackColor: palette.rule,
        thumbColor: palette.ink,
        overlayColor: Colors.transparent,
        trackHeight: 1.5,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.ink,
        linearTrackColor: palette.rule,
        circularTrackColor: palette.rule,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: palette.inverseCanvas),
        textStyle: TextStyle(color: palette.inverseInk, fontSize: 12),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _PaperPageTransitionsBuilder(),
          TargetPlatform.linux: _PaperPageTransitionsBuilder(),
          TargetPlatform.iOS: _PaperPageTransitionsBuilder(),
          TargetPlatform.macOS: _PaperPageTransitionsBuilder(),
        },
      ),
      extensions: <ThemeExtension<dynamic>>[
        PaperTypography(palette: palette, options: typeOptions),
      ],
    );
  }
}

/// A page transition with no scale, no elevation and no shadow.
///
/// Horizontal motion only, and only 6% opacity cross-fade on top. This reads
/// as turning a page rather than as a Material "shared axis", and it keeps
/// e-ink panels from having to redraw a large translucent layer.
class _PaperPageTransitionsBuilder extends PageTransitionsBuilder {
  const _PaperPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) return child;

    final Animation<double> eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.06, 0),
        end: Offset.zero,
      ).animate(eased),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.94, end: 1).animate(eased),
        child: child,
      ),
    );
  }
}
