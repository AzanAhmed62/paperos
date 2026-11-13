import 'package:flutter/material.dart';

import '../core/display/display_policy.dart';
import '../shared/widgets/paper_widgets.dart';
import '../theme/paper_palette.dart';
import '../theme/paper_space.dart';
import '../theme/paper_typography.dart';

/// The top-level destinations of PaperOS.
enum PaperDestination {
  home('home', 'Home', Icons.home_outlined),
  library('library', 'Library', Icons.menu_book_outlined),
  files('files', 'Files', Icons.folder_outlined),
  notes('notes', 'Notes', Icons.edit_note_outlined),
  settings('settings', 'Settings', Icons.tune_outlined);

  const PaperDestination(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;
}

/// The bottom strip of PaperOS destinations.
///
/// The bar is a bespoke strip of icon and label rather than a
/// [NavigationBar]: PaperOS has no accent colour to tint a Material indicator
/// with, and the selected item is shown the way the rest of the product shows
/// selection — inverted.
class PaperDestinationBar extends StatelessWidget {
  const PaperDestinationBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.canvas,
        border: Border(top: BorderSide(color: palette.rule)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: <Widget>[
              for (final PaperDestination destination
                  in PaperDestination.values)
                Expanded(
                  child: _DestinationButton(
                    key: ValueKey<String>('dest-${destination.path}'),
                    destination: destination,
                    selected: destination.index == currentIndex,
                    onTap: () => onSelect(destination.index),
                    palette: palette,
                    type: type,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinationButton extends StatelessWidget {
  const _DestinationButton({
    super.key,
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.palette,
    required this.type,
  });

  final PaperDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final PaperPalette palette;
  final PaperTypography type;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? palette.inverseInk : palette.inkMuted;
    final DisplayPolicy display = DisplayPolicyScope.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // The selection marker is a 2pt rule above the icon, the same
            // "inverted" language used by chips and the reader control bar.
            AnimatedContainer(
              duration: display.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              height: 2,
              width: selected ? 20 : 0,
              color: palette.inverseCanvas,
            ),
            const SizedBox(height: PaperSpace.xs + PaperSpace.xs),
            Icon(destination.icon, size: 20, color: color),
            const SizedBox(height: PaperSpace.xxs + PaperSpace.xs),
            Text(
              destination.label,
              style: type.navLabel.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
