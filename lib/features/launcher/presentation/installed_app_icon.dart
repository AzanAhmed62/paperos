import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/platform/installed_app.dart';
import '../../../shared/widgets/paper_widgets.dart';
import '../../../theme/paper_palette.dart';
import '../../../theme/paper_typography.dart';

/// A launcher icon rendered from the platform, with a typographic fallback.
///
/// Icons are requested lazily by the widget that needs them: asking Android to
/// rasterise every installed icon up front would make the drawer feel slow for
/// the dozen the user actually looks at. The catalogue caches the bytes for the
/// rest of the session, so moving between Home and the drawer is free.
class InstalledAppIcon extends ConsumerStatefulWidget {
  const InstalledAppIcon({
    super.key,
    required this.app,
    this.size = 32,
    this.showIcon = true,
  });

  final InstalledApp app;
  final double size;

  /// When false, only the initial is drawn. This is the "Show app icons"
  /// preference, and it avoids even asking the platform for a bitmap.
  final bool showIcon;

  @override
  ConsumerState<InstalledAppIcon> createState() => _InstalledAppIconState();
}

class _InstalledAppIconState extends ConsumerState<InstalledAppIcon> {
  Uint8List? _bytes;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(InstalledAppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.packageName != widget.app.packageName ||
        oldWidget.showIcon != widget.showIcon) {
      _requested = false;
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    if (!widget.showIcon || _requested) return;
    _requested = true;
    final Uint8List? bytes = await ref
        .read(appCatalogProvider)
        .icon(widget.app.packageName);
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = widget.showIcon ? _bytes : null;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: bytes == null
          ? _Fallback(app: widget.app)
          : Image.memory(
              bytes,
              width: widget.size,
              height: widget.size,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stack) {
                    return _Fallback(app: widget.app);
                  },
            ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.app});

  final InstalledApp app;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: palette.rule)),
      child: Center(
        child: Text(
          _initial(app.label),
          style: PaperTypography.of(context).meta,
        ),
      ),
    );
  }

  /// First letter of the label, so a tile is never a blank square.
  static String _initial(String label) {
    final String trimmed = label.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }
}
