import 'package:flutter/material.dart';

/// Scroll physics for the E-Ink profile.
///
/// Drag remains available — a reader must still be able to move through a
/// long chapter — but the lift-off fling is disabled. Coaxing a panel through
/// a decelerating animation is exactly the kind of continuous redraw the
/// profile exists to avoid.
class PaperStaticScrollPhysics extends ClampingScrollPhysics {
  const PaperStaticScrollPhysics({super.parent});

  @override
  double get maxFlingVelocity => 0;

  @override
  PaperStaticScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      PaperStaticScrollPhysics(parent: buildParent(ancestor));
}

/// Applies the display policy to every scrollable in the application.
///
/// This lives above the Navigator so library lists, the EPUB scrolling flow,
/// settings and sheet contents all share the same behaviour.
class PaperScrollBehavior extends MaterialScrollBehavior {
  const PaperScrollBehavior({required this.reduceMotion});

  final bool reduceMotion;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final ScrollPhysics standard = super.getScrollPhysics(context);
    if (!reduceMotion) return standard;
    return const PaperStaticScrollPhysics().applyTo(standard);
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // The overscroll glow/stretch is a decorative animation; it adds motion
    // without adding information.
    if (reduceMotion) return child;
    return super.buildOverscrollIndicator(context, child, details);
  }
}
