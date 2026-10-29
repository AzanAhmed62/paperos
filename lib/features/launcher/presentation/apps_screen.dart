import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/paper_exception.dart';
import '../../../core/platform/installed_app.dart';
import '../../../shared/widgets/paper_widgets.dart';
import '../../../theme/paper_palette.dart';
import '../../../theme/paper_space.dart';
import '../../../theme/paper_typography.dart';
import '../application/launcher_providers.dart';

/// The app drawer.
///
/// A launcher is only as good as this screen, so it is a plain, ordered,
/// searchable list of what is actually installed. It reports honestly when the
/// platform will not tell it: a launcher that silently shows nothing is worse
/// than one that explains the package-visibility limit.
class AppsScreen extends ConsumerStatefulWidget {
  const AppsScreen({super.key});

  @override
  ConsumerState<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends ConsumerState<AppsScreen> {
  @override
  Widget build(BuildContext context) {
    final AppCatalogSupport support = ref.watch(appCatalogSupportProvider);
    final AsyncValue<List<InstalledApp>> apps = ref.watch(visibleAppsProvider);
    final String query = ref.watch(appSearchProvider);

    return Scaffold(
      appBar: PaperTopBar(
        title: 'Apps',
        subtitle: _subtitleFor(apps.value),
        onBack: () => Navigator.of(context).maybePop(),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              PaperSpace.gutter,
              0,
              PaperSpace.gutter,
              PaperSpace.sm,
            ),
            child: PaperSearchField(
              hintText: 'Search apps',
              autofocus: true,
              onChanged: ref.read(appSearchProvider.notifier).set,
            ),
          ),
        ),
      ),
      body: switch (support) {
        AppCatalogSupport.unsupported => const PaperEmptyState(
          title: 'App list unavailable',
          message:
              'PaperOS can only read the installed app list on Android. '
              'This platform does not provide it.',
          icon: Icons.apps_outlined,
        ),
        AppCatalogSupport.restricted => const _RestrictedNotice(),
        AppCatalogSupport.full => apps.when(
          loading: () => const PaperLoading(label: 'Reading installed apps'),
          error: (Object error, StackTrace stack) => PaperErrorView(
            message: switch (error) {
              final PaperException failure => failure.message,
              _ => 'The installed app list could not be read.',
            },
            onRetry: () => ref.invalidate(installedAppsProvider),
          ),
          data: (List<InstalledApp> items) {
            if (items.isEmpty) {
              return PaperEmptyState(
                title: query.isEmpty
                    ? 'No launchable apps found'
                    : 'No matches',
                message: query.isEmpty
                    ? 'Android reported no launchable activities. This usually '
                          'means the app list query was blocked.'
                    : 'No installed app matches "$query".',
                icon: Icons.search_off_outlined,
                action: query.isEmpty
                    ? null
                    : PaperButton(
                        label: 'Clear search',
                        onPressed: ref.read(appSearchProvider.notifier).clear,
                      ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: PaperSpace.xxl),
              itemCount: items.length,
              itemBuilder: (BuildContext context, int index) {
                final InstalledApp app = items[index];
                return _AppRow(app: app, showRule: index != items.length - 1);
              },
            );
          },
        ),
      },
    );
  }

  String? _subtitleFor(List<InstalledApp>? apps) {
    if (apps == null || apps.isEmpty) return null;
    return '${apps.length} app${apps.length == 1 ? '' : 's'}';
  }
}

/// Shown when Android returned a list that is almost certainly incomplete.
///
/// This is the Android 11+ package-visibility failure mode, and the user can
/// only fix it by knowing about it.
class _RestrictedNotice extends StatelessWidget {
  const _RestrictedNotice();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const PaperEmptyState(
          title: 'The app list looks incomplete',
          message:
              'Android 11 and later hide apps from other apps unless they '
              'are declared in the manifest. PaperOS declares what it needs, so '
              'a short list usually means a restricted profile or a work '
              'device.',
          icon: Icons.info_outline,
        ),
        PaperButton(
          label: 'Reload',
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pull the list again from Settings.')),
          ),
        ),
      ],
    );
  }
}

class _AppRow extends ConsumerWidget {
  const _AppRow({required this.app, required this.showRule});

  final InstalledApp app;
  final bool showRule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PaperPalette palette = paperPalette(context);

    return Column(
      children: <Widget>[
        PaperListTile(
          title: app.label.isEmpty ? app.packageName : app.label,
          subtitle: app.packageName,
          leading: _AppIcon(app: app, palette: palette),
          trailing: Icon(Icons.north_east, size: 16, color: palette.inkFaint),
          semanticLabel: 'Launch ${app.label}',
          onTap: () => _launch(context, ref),
        ),
        if (showRule) const PaperRule(inset: PaperSpace.gutter),
      ],
    );
  }

  Future<void> _launch(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(launcherServiceProvider).launchApp(app);
    } on PaperException catch (error) {
      if (!context.mounted) return;
      PaperToast.show(context, error.message, icon: Icons.error_outline);
    }
  }
}

/// The launcher icon, rendered from the platform on first use and cached in
/// memory for the rest of the session.
///
/// Icons are requested lazily by the row that needs them: asking Android to
/// rasterise 200 icons up front would make the drawer feel slow for the dozen
/// the user actually looks at.
class _AppIcon extends ConsumerStatefulWidget {
  const _AppIcon({required this.app, required this.palette});

  final InstalledApp app;
  final PaperPalette palette;

  @override
  ConsumerState<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends ConsumerState<_AppIcon> {
  Uint8List? _bytes;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_AppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.packageName != widget.app.packageName) _load();
  }

  Future<void> _load() async {
    if (_requested) return;
    _requested = true;
    final Uint8List? bytes = await ref
        .read(appCatalogProvider)
        .icon(widget.app.packageName);
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = _bytes;
    return SizedBox(
      width: 32,
      height: 32,
      child: bytes == null
          ? DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: widget.palette.rule),
              ),
              child: Center(
                child: Text(
                  _initial(),
                  style: PaperTypography.of(context).meta,
                ),
              ),
            )
          : Image.memory(
              bytes,
              width: 32,
              height: 32,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stack) {
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: widget.palette.rule),
                      ),
                      child: Center(
                        child: Text(
                          _initial(),
                          style: PaperTypography.of(context).meta,
                        ),
                      ),
                    );
                  },
            ),
    );
  }

  /// First letter of the label, so a row is never a blank square.
  String _initial() {
    final String label = widget.app.label.trim();
    if (label.isEmpty) return '?';
    return label.characters.first.toUpperCase();
  }
}
