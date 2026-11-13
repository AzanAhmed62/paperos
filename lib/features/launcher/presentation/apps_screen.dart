import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/paper_exception.dart';
import '../../../core/platform/installed_app.dart';
import '../../../shared/widgets/paper_widgets.dart';
import '../../../theme/paper_palette.dart';
import '../../../theme/paper_space.dart';
import '../../../theme/paper_typography.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/app_settings.dart';
import '../application/launcher_providers.dart';
import 'installed_app_icon.dart';

/// The app drawer.
///
/// A launcher is only as good as this screen, so it is a plain, ordered,
/// searchable list of what is actually installed. Favourites and recents are
/// shortcuts into the same catalogue, not a second list: an app can be pinned
/// from its row and still appears in the full alphabetical list below.
///
/// It reports honestly when the platform will not tell it: a launcher that
/// silently shows nothing is worse than one that explains the package-visibility
/// limit.
class AppsScreen extends ConsumerWidget {
  const AppsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppCatalogSupport support = ref.watch(appCatalogSupportProvider);
    final bool restricted = ref.watch(appCatalogRestrictedProvider);
    final AsyncValue<List<InstalledApp>> apps = ref.watch(visibleAppsProvider);
    final LauncherSettings launcher = ref.watch(settingsProvider).launcher;
    final String query = ref.watch(appSearchProvider);
    final LauncherActions actions = ref.read(launcherActionsProvider);

    return Scaffold(
      appBar: PaperTopBar(
        title: 'Apps',
        subtitle: _subtitleFor(apps.value),
        onBack: () => Navigator.of(context).maybePop(),
        actions: <Widget>[
          IconButton(
            onPressed: apps.isLoading ? null : actions.refreshApps,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh apps',
          ),
        ],
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
        AppCatalogSupport.restricted => _RestrictedNotice(
          onReload: actions.refreshApps,
        ),
        AppCatalogSupport.full => apps.when(
          loading: () => const PaperLoading(label: 'Reading installed apps'),
          error: (Object error, StackTrace stack) => PaperErrorView(
            message: switch (error) {
              final PaperException failure => failure.message,
              _ => 'The installed app list could not be read.',
            },
            onRetry: actions.refreshApps,
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
                    ? PaperButton(
                        label: 'Reload',
                        onPressed: actions.refreshApps,
                      )
                    : PaperButton(
                        label: 'Clear search',
                        onPressed: ref.read(appSearchProvider.notifier).clear,
                      ),
              );
            }
            return _AppList(
              items: items,
              query: query,
              restricted: restricted,
              showIcons: launcher.showIcons,
              onReload: actions.refreshApps,
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

class _AppList extends ConsumerWidget {
  const _AppList({
    required this.items,
    required this.query,
    required this.restricted,
    required this.showIcons,
    required this.onReload,
  });

  final List<InstalledApp> items;
  final String query;
  final bool restricted;
  final bool showIcons;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<InstalledApp> favorites = ref.watch(favoriteAppsProvider);
    final List<InstalledApp> recents = ref.watch(recentAppsProvider);

    final List<Widget> header = <Widget>[
      if (restricted) _RestrictedBanner(onReload: onReload),
      if (query.isEmpty && favorites.isNotEmpty)
        _AppStrip(
          label: 'Pinned',
          apps: favorites,
          showIcons: showIcons,
          onLongPress: (InstalledApp app) =>
              ref.read(launcherActionsProvider).toggleFavorite(app),
        ),
      if (query.isEmpty && recents.isNotEmpty)
        _AppStrip(
          label: 'Recent',
          apps: recents,
          showIcons: showIcons,
          trailing: PaperTextAction(
            label: 'Clear',
            onPressed: ref.read(launcherActionsProvider).clearRecents,
          ),
        ),
      if (query.isEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(
            PaperSpace.gutter,
            PaperSpace.md,
            PaperSpace.gutter,
            PaperSpace.sm,
          ),
          child: PaperSectionLabel('All apps'),
        ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: PaperSpace.xxl),
      itemCount: header.length + items.length,
      itemBuilder: (BuildContext context, int index) {
        if (index < header.length) return header[index];
        final int appIndex = index - header.length;
        final InstalledApp app = items[appIndex];
        return _AppRow(
          app: app,
          showIcons: showIcons,
          showRule: appIndex != items.length - 1,
        );
      },
    );
  }
}

/// A horizontal shortcut strip for pinned or recent apps.
class _AppStrip extends ConsumerWidget {
  const _AppStrip({
    required this.label,
    required this.apps,
    required this.showIcons,
    this.onLongPress,
    this.trailing,
  });

  final String label;
  final List<InstalledApp> apps;
  final bool showIcons;
  final ValueChanged<InstalledApp>? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PaperSpace.gutter,
            PaperSpace.md,
            PaperSpace.gutter,
            PaperSpace.sm,
          ),
          child: PaperSectionLabel(label, trailing: trailing),
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: PaperSpace.gutter),
            itemCount: apps.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: PaperSpace.md),
            itemBuilder: (BuildContext context, int index) {
              final InstalledApp app = apps[index];
              return _StripTile(
                app: app,
                showIcon: showIcons,
                onTap: () => _launch(context, ref, app),
                onLongPress: onLongPress == null
                    ? null
                    : () => onLongPress!(app),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _launch(
    BuildContext context,
    WidgetRef ref,
    InstalledApp app,
  ) async {
    try {
      await ref.read(launcherActionsProvider).launch(app);
    } on PaperException catch (error) {
      if (!context.mounted) return;
      PaperToast.show(context, error.message, icon: Icons.error_outline);
    }
  }
}

class _StripTile extends StatelessWidget {
  const _StripTile({
    required this.app,
    required this.showIcon,
    required this.onTap,
    this.onLongPress,
  });

  final InstalledApp app;
  final bool showIcon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);

    return Semantics(
      button: true,
      label: 'Open ${app.label}',
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              InstalledAppIcon(app: app, size: 40, showIcon: showIcon),
              const SizedBox(height: PaperSpace.xs),
              Text(
                app.label.isEmpty ? app.packageName : app.label,
                style: type.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when Android returned a list that is almost certainly incomplete.
///
/// This is the Android 11+ package-visibility failure mode, and the user can
/// only fix it by knowing about it.
class _RestrictedNotice extends StatelessWidget {
  const _RestrictedNotice({required this.onReload});

  final VoidCallback onReload;

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
        PaperButton(label: 'Reload', onPressed: onReload),
      ],
    );
  }
}

class _RestrictedBanner extends StatelessWidget {
  const _RestrictedBanner({required this.onReload});

  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PaperSpace.gutter,
        PaperSpace.md,
        PaperSpace.gutter,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: palette.rule)),
        child: Padding(
          padding: const EdgeInsets.all(PaperSpace.md),
          child: Row(
            children: <Widget>[
              Icon(Icons.info_outline, size: 18, color: palette.inkMuted),
              const SizedBox(width: PaperSpace.sm),
              Expanded(
                child: Text(
                  'Android reported very few apps. The list may be restricted.',
                  style: PaperTypography.of(context).bodyQuiet,
                ),
              ),
              PaperTextAction(label: 'Reload', onPressed: onReload),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppRow extends ConsumerWidget {
  const _AppRow({
    required this.app,
    required this.showIcons,
    required this.showRule,
  });

  final InstalledApp app;
  final bool showIcons;
  final bool showRule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PaperPalette palette = paperPalette(context);
    final bool pinned = ref.watch(
      settingsProvider.select(
        (AppSettings settings) =>
            settings.launcher.favoritePackages.contains(app.packageName),
      ),
    );

    return Column(
      children: <Widget>[
        PaperListTile(
          title: app.label.isEmpty ? app.packageName : app.label,
          subtitle: app.packageName,
          leading: InstalledAppIcon(app: app, size: 32, showIcon: showIcons),
          trailing: IconButton(
            onPressed: () =>
                ref.read(launcherActionsProvider).toggleFavorite(app),
            icon: Icon(
              pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 20,
            ),
            color: pinned ? palette.ink : palette.inkFaint,
            tooltip: pinned ? 'Unpin ${app.label}' : 'Pin ${app.label}',
          ),
          semanticLabel: 'Launch ${app.label}',
          onTap: () => _launch(context, ref),
          onLongPress: () =>
              ref.read(launcherActionsProvider).toggleFavorite(app),
        ),
        if (showRule) const PaperRule(inset: PaperSpace.gutter),
      ],
    );
  }

  Future<void> _launch(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(launcherActionsProvider).launch(app);
    } on PaperException catch (error) {
      if (!context.mounted) return;
      PaperToast.show(context, error.message, icon: Icons.error_outline);
    }
  }
}
