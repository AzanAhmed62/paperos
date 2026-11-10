import 'package:flutter/material.dart';

import '../../core/display/display_policy.dart';
import '../../theme/paper_palette.dart';
import '../../theme/paper_space.dart';
import '../../theme/paper_typography.dart';

/// Shared presentation vocabulary.
///
/// Every screen in PaperOS is built from these widgets, which is what makes
/// unrelated screens look like one product: the same row height, the same
/// divider, the same empty state, the same press feedback.

/// Reads the palette resolved for the active [PaperStyle].
PaperPalette paperPalette(BuildContext context) =>
    PaperPalette.of(PaperTypography.of(context).palette.style);

/// Animation override for framework-created modal surfaces.
///
/// The E-Ink profile must reach sheets and dialogs too, not only the routes
/// PaperOS builds itself: both are pushed on the Navigator above this widget
/// and would otherwise keep Material's enter/exit animation.
AnimationStyle? paperModalAnimationStyle(BuildContext context) =>
    DisplayPolicyScope.of(context).reduceMotion
    ? AnimationStyle.noAnimation
    : null;

/// The screen background plus a hairline divider used as the closing edge of a
/// section.
class PaperSection extends StatelessWidget {
  const PaperSection({
    super.key,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      PaperSpace.gutter,
      PaperSpace.xl,
      PaperSpace.gutter,
      PaperSpace.lg,
    ),
  });

  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: padding, child: child);
  }
}

/// Small uppercase-free section label with an optional hairline that runs to
/// the right edge.
class PaperSectionLabel extends StatelessWidget {
  const PaperSectionLabel(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(label, style: PaperTypography.of(context).sectionLabel),
        const SizedBox(width: PaperSpace.md),
        Expanded(child: Divider(color: palette.rule, height: 1)),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: PaperSpace.md),
          trailing!,
        ],
      ],
    );
  }
}

/// The PaperOS list row: fixed rhythm, no ripple, no elevation.
class PaperListTile extends StatelessWidget {
  const PaperListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.dense = false,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool dense;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);
    final PaperPalette palette = type.palette;
    final bool tappable = onTap != null || onLongPress != null;

    return Semantics(
      button: tappable,
      selected: selected,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        // No splash: see PaperTheme for why PaperOS has no ripples.
        splashFactory: NoSplash.splashFactory,
        highlightColor: selected
            ? palette.inverseCanvas.withValues(alpha: 0.06)
            : null,
        child: Container(
          color: selected
              ? palette.inverseCanvas.withValues(alpha: 0.08)
              : null,
          padding: EdgeInsets.symmetric(
            horizontal: PaperSpace.gutter,
            vertical: dense ? PaperSpace.sm + PaperSpace.xxs : PaperSpace.md,
          ),
          child: Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: PaperSpace.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: selected
                          ? type.listTitle.copyWith(fontWeight: FontWeight.w600)
                          : type.listTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: PaperSpace.xxs),
                        child: Text(
                          subtitle!,
                          style: type.listSubtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: PaperSpace.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A hairline between rows. Explicit rather than [Divider] so that the colour
/// and inset are always the design system's.
class PaperRule extends StatelessWidget {
  const PaperRule({super.key, this.inset = 0, this.strong = false});

  final double inset;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    return Container(
      height: 1,
      margin: EdgeInsets.only(left: inset),
      color: strong ? palette.ruleStrong : palette.rule,
    );
  }
}

/// Horizontal progress indicator in the PaperOS idiom: a 2pt track, no
/// animation on the value itself, and a percentage label when asked for.
class PaperProgressBar extends StatelessWidget {
  const PaperProgressBar({
    super.key,
    required this.value,
    this.height = 2,
    this.showLabel = false,
  });

  /// 0..1. Values outside the range are clamped, not asserted: a bad progress
  /// value must never crash a list.
  final double value;
  final double height;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);
    final double fraction = value.isNaN ? 0 : value.clamp(0.0, 1.0);

    if (!showLabel) {
      return ClipRect(
        child: SizedBox(
          height: height,
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: height,
            backgroundColor: palette.rule,
            valueColor: AlwaysStoppedAnimation<Color>(palette.ink),
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: ClipRect(
            child: SizedBox(
              height: height,
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: height,
                backgroundColor: palette.rule,
                valueColor: AlwaysStoppedAnimation<Color>(palette.ink),
              ),
            ),
          ),
        ),
        const SizedBox(width: PaperSpace.sm),
        Text('${(fraction * 100).round()}%', style: type.percent),
      ],
    );
  }
}

/// A text action. PaperOS has no filled buttons anywhere: the only filled
/// element in the product is the inverted selection, so a "primary button"
/// would break the visual rule.
class PaperButton extends StatelessWidget {
  const PaperButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.emphasised = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool emphasised;

  /// When true the button fills the available width, for the bottom of a sheet.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);
    final DisplayPolicy display = DisplayPolicyScope.of(context);
    final bool enabled = onPressed != null;
    final Color foreground = emphasised
        ? palette.inverseInk
        : (enabled ? palette.ink : palette.inkFaint);

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: PaperSpace.sm),
        ],
        Flexible(
          child: Text(
            label,
            style: type.action.copyWith(color: foreground),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: emphasised ? palette.inverseCanvas : Colors.transparent,
        shape: const RoundedRectangleBorder(),
        child: InkWell(
          onTap: onPressed,
          splashFactory: NoSplash.splashFactory,
          child: Container(
            constraints: BoxConstraints(
              minHeight: display.largeTargets ? 48 : 44,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: PaperSpace.lg,
              vertical: PaperSpace.sm + PaperSpace.xs,
            ),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// A selectable chip. Used for library scopes, task filters and settings
/// choices. Selected chips are inverted, which is the only filled element in
/// the app.
class PaperChip extends StatelessWidget {
  const PaperChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  /// A disabled chip still shows the effective state but cannot be changed.
  /// The reading settings use this for choices the E-Ink profile forces.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);
    final DisplayPolicy display = DisplayPolicyScope.of(context);
    final Color foreground = selected ? palette.inverseInk : palette.inkMuted;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      child: InkWell(
        onTap: enabled ? onTap : null,
        splashFactory: NoSplash.splashFactory,
        child: Container(
          constraints: BoxConstraints(
            // E-Ink uses the full 48dp accessibility touch target; the
            // standard profile keeps the compact type-first chip.
            minHeight: display.largeTargets ? 48 : 32,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: PaperSpace.md,
            vertical: display.largeTargets ? PaperSpace.sm : PaperSpace.xs * 2,
          ),
          decoration: BoxDecoration(
            color: selected ? palette.inverseCanvas : Colors.transparent,
            border: Border.all(
              color: selected ? palette.inverseCanvas : palette.rule,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: PaperSpace.xs + PaperSpace.xs),
              ],
              Text(
                label,
                style: type.meta.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The empty state: a short line of text and, optionally, one action.
///
/// PaperOS never fills an empty screen with an illustration or a sample
/// record. It says what is missing and offers the one thing that fixes it.
class PaperEmptyState extends StatelessWidget {
  const PaperEmptyState({
    super.key,
    required this.title,
    this.message,
    this.action,
    this.icon,
  });

  final String title;
  final String? message;
  final Widget? action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);
    final PaperPalette palette = type.palette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PaperSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 28, color: palette.inkFaint),
              const SizedBox(height: PaperSpace.lg),
            ],
            Text(title, style: type.heading, textAlign: TextAlign.center),
            if (message != null) ...<Widget>[
              const SizedBox(height: PaperSpace.sm),
              Text(
                message!,
                style: type.bodyQuiet,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: PaperSpace.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A quiet progress indicator that respects the display profile.
///
/// An indeterminate spinner repaints forever and smears on an electrophoretic
/// panel. The E-Ink profile therefore draws a static quarter ring; the standard
/// profile keeps the ordinary animation.
class PaperProgress extends StatelessWidget {
  const PaperProgress({
    super.key,
    this.size = 18,
    this.strokeWidth = 1.5,
    this.semanticsLabel,
  });

  final double size;
  final double strokeWidth;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final DisplayPolicy display = DisplayPolicyScope.of(context);

    return SizedBox(
      width: size,
      height: size,
      child: Semantics(
        label: semanticsLabel,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          backgroundColor: palette.rule,
          value: display.reduceMotion ? 0.25 : null,
          valueColor: AlwaysStoppedAnimation<Color>(palette.ink),
        ),
      ),
    );
  }
}

/// Centred, quiet progress indicator used while a screen's data is loading.
class PaperLoading extends StatelessWidget {
  const PaperLoading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PaperProgress(semanticsLabel: label ?? 'Loading'),
          if (label != null) ...<Widget>[
            const SizedBox(height: PaperSpace.md),
            Text(label!, style: type.bodyQuiet),
          ],
        ],
      ),
    );
  }
}

/// Error state with a retry. [onRetry] is required because an error the user
/// cannot act on is a dead end.
class PaperErrorView extends StatelessWidget {
  const PaperErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = 'Something went wrong',
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return PaperEmptyState(
      title: title,
      message: message,
      action: PaperButton(
        label: 'Try again',
        onPressed: onRetry,
        icon: Icons.refresh,
      ),
    );
  }
}

/// The PaperOS app bar: a screen title, optional trailing actions, and no
/// elevation. Replaces [AppBar] everywhere so no screen can accidentally
/// reintroduce a Material shadow.
class PaperTopBar extends StatelessWidget implements PreferredSizeWidget {
  const PaperTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.leading,
    this.onBack,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;
  final VoidCallback? onBack;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(56 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);
    final PaperPalette palette = type.palette;

    return AppBar(
      backgroundColor: palette.canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: PaperSpace.gutter,
      leading: leading ?? _backButton(context, onBack),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title, style: type.screenTitle),
          if (subtitle != null)
            Text(
              subtitle!,
              style: type.meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      actions: <Widget>[
        ...actions,
        const SizedBox(width: PaperSpace.sm),
      ],
      bottom: bottom,
    );
  }

  Widget? _backButton(BuildContext context, VoidCallback? onBack) {
    if (onBack == null && !Navigator.of(context).canPop()) return null;
    return IconButton(
      onPressed: onBack ?? () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    );
  }
}

/// A search field in the PaperOS idiom: underlined, no fill, no rounded pill.
class PaperSearchField extends StatefulWidget {
  const PaperSearchField({
    super.key,
    required this.onChanged,
    this.controller,
    this.hintText = 'Search',
    this.autofocus = false,
    this.onSubmitted,
  });

  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final String hintText;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PaperSearchField> createState() => _PaperSearchFieldState();
}

class _PaperSearchFieldState extends State<PaperSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    // The suffix button depends on the controller's text, and that text also
    // changes when a parent clears or replaces it. Rebuild on every edit.
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (widget.controller == null) _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);

    return TextField(
      controller: _controller,
      focusNode: _focus,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: type.input,
      cursorColor: palette.ink,
      cursorHeight: 18,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText,
        hintStyle: type.input.copyWith(color: palette.inkFaint),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: PaperSpace.sm),
        prefixIcon: Icon(Icons.search, size: 20, color: palette.inkFaint),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 28,
          minHeight: 28,
        ),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Clear',
              ),
      ),
    );
  }
}

/// A form row: label above, control below, optional helper copy.
class PaperField extends StatelessWidget {
  const PaperField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
  });

  final String label;
  final Widget child;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PaperSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: type.fieldLabel),
          const SizedBox(height: PaperSpace.xs + PaperSpace.xs),
          child,
          if (helper != null) ...<Widget>[
            const SizedBox(height: PaperSpace.xs),
            Text(helper!, style: type.caption),
          ],
        ],
      ),
    );
  }
}

/// A row with a label on the left and any control on the right, with a
/// hairline between instances.
class PaperSettingRow extends StatelessWidget {
  const PaperSettingRow({
    super.key,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.leading,
  });

  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);

    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PaperSpace.gutter,
        vertical: PaperSpace.md,
      ),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: PaperSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: type.body),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: PaperSpace.xxs),
                  Text(subtitle!, style: type.caption),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: PaperSpace.md),
            trailing!,
          ] else if (onTap != null) ...<Widget>[
            const SizedBox(width: PaperSpace.sm),
            Icon(Icons.chevron_right, size: 18, color: palette.inkFaint),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      child: row,
    );
  }
}

/// A switch that matches the monochrome palette.
class PaperSwitch extends StatelessWidget {
  const PaperSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: palette.inverseInk,
      activeTrackColor: palette.inverseCanvas,
      inactiveThumbColor: palette.raised,
      inactiveTrackColor: palette.rule,
      trackOutlineColor: WidgetStatePropertyAll<Color>(palette.ruleStrong),
    );
  }
}

/// A stepper row for numeric settings: label, value, minus, plus.
class PaperStepper extends StatelessWidget {
  const PaperStepper({
    super.key,
    required this.label,
    required this.display,
    required this.onDecrease,
    required this.onIncrease,
    this.canDecrease = true,
    this.canIncrease = true,
  });

  final String label;
  final String display;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final bool canDecrease;
  final bool canIncrease;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);
    final DisplayPolicy displayPolicy = DisplayPolicyScope.of(context);

    return Semantics(
      label: label,
      value: display,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PaperSpace.gutter,
          vertical: PaperSpace.sm,
        ),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label, style: type.body)),
            _StepButton(
              icon: Icons.remove,
              onTap: canDecrease ? onDecrease : null,
              tooltip: 'Decrease $label',
              palette: palette,
              size: displayPolicy.largeTargets ? 48 : 36,
            ),
            SizedBox(
              width: 72,
              child: Text(
                display,
                textAlign: TextAlign.center,
                style: type.body.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            _StepButton(
              icon: Icons.add,
              onTap: canIncrease ? onIncrease : null,
              tooltip: 'Increase $label',
              palette: palette,
              size: displayPolicy.largeTargets ? 48 : 36,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    required this.palette,
    required this.size,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final PaperPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border.all(color: palette.rule)),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? palette.ink : palette.inkFaint,
          ),
        ),
      ),
    );
  }
}

/// A bare text action with no button chrome, for inline links inside a section
/// ("Library", "All", "Add").
class PaperTextAction extends StatelessWidget {
  const PaperTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);
    final bool enabled = onPressed != null;

    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PaperSpace.xs,
          vertical: PaperSpace.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: type.action.copyWith(
                color: enabled ? palette.ink : palette.inkFaint,
              ),
            ),
            if (icon != null) ...<Widget>[
              const SizedBox(width: PaperSpace.xxs),
              Icon(icon, size: 14, color: palette.ink),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single-line text prompt.
///
/// Returns the entered text, or null when the user dismisses the sheet. Built
/// on a modal bottom sheet rather than a dialog because a keyboard opening over
/// a centred dialog on a phone leaves almost no room for the field.
Future<String?> showPaperTextPrompt(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
  String confirmLabel = 'Save',
  String cancelLabel = 'Cancel',
  TextInputType keyboardType = TextInputType.text,
  int maxLength = 200,
}) {
  return showModalBottomSheet<String>(
    context: context,
    sheetAnimationStyle: paperModalAnimationStyle(context),
    isScrollControlled: true,
    backgroundColor: paperPalette(context).canvas,
    barrierColor: paperPalette(context).ink.withValues(alpha: 0.32),
    shape: const RoundedRectangleBorder(),
    builder: (BuildContext sheetContext) {
      return _PaperTextPromptSheet(
        title: title,
        label: label,
        initialValue: initialValue,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        keyboardType: keyboardType,
        maxLength: maxLength,
      );
    },
  );
}

class _PaperTextPromptSheet extends StatefulWidget {
  const _PaperTextPromptSheet({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.keyboardType,
    required this.maxLength,
  });

  final String title;
  final String label;
  final String initialValue;
  final String confirmLabel;
  final String cancelLabel;
  final TextInputType keyboardType;
  final int maxLength;

  @override
  State<_PaperTextPromptSheet> createState() => _PaperTextPromptSheetState();
}

class _PaperTextPromptSheetState extends State<_PaperTextPromptSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Focus after the sheet's entrance animation, otherwise the keyboard and
    // the sheet animate in at the same time and the field is hidden behind it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PaperSpace.gutter,
            PaperSpace.lg,
            PaperSpace.gutter,
            PaperSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(widget.title, style: type.heading),
              const SizedBox(height: PaperSpace.md),
              TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: false,
                keyboardType: widget.keyboardType,
                maxLength: widget.maxLength,
                textInputAction: TextInputAction.done,
                onSubmitted: (String _) => _submit(),
                style: type.input,
                cursorColor: palette.ink,
                decoration: InputDecoration(
                  hintText: widget.label,
                  hintStyle: type.input.copyWith(color: palette.inkFaint),
                  counterText: '',
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: palette.rule),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: palette.ink, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: PaperSpace.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  PaperButton(
                    label: widget.cancelLabel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: PaperSpace.sm),
                  PaperButton(
                    label: widget.confirmLabel,
                    emphasised: true,
                    onPressed: _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirms an action that cannot be undone, such as deleting PaperOS' copy of
/// an imported document.
///
/// Returns false when the user dismisses the dialog. A destructive action
/// always names the specific thing being removed rather than saying "are you
/// sure?".
Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) async {
  final PaperPalette palette = paperPalette(context);
  final PaperTypography type = PaperTypography.of(context);

  final bool? confirmed = await showDialog<bool>(
    context: context,
    animationStyle: paperModalAnimationStyle(context),
    barrierColor: palette.ink.withValues(alpha: 0.32),
    builder: (BuildContext dialogContext) {
      return Dialog(
        backgroundColor: palette.canvas,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(PaperSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: type.heading),
              const SizedBox(height: PaperSpace.sm),
              Text(message, style: type.bodyQuiet),
              const SizedBox(height: PaperSpace.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  PaperButton(
                    label: cancelLabel,
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                  ),
                  const SizedBox(width: PaperSpace.sm),
                  PaperButton(
                    label: confirmLabel,
                    emphasised: true,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return confirmed ?? false;
}

/// Shows a short, self-dismissing message at the bottom of the screen.
///
/// Used for the results of actions that have no other place to report
/// themselves, such as "Imported" or "Removed".
class PaperToast {
  const PaperToast._();

  static void show(BuildContext context, String message, {IconData? icon}) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: palette.inverseCanvas,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(PaperSpace.lg),
        width: null,
        shape: const RoundedRectangleBorder(),
        content: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 18, color: palette.inverseInk),
              const SizedBox(width: PaperSpace.md),
            ],
            Expanded(
              child: Text(
                message,
                style: type.meta.copyWith(color: palette.inverseInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
