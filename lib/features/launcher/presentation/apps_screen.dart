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
        AppCatalogSupport.restricted => PaperEmptyState(
          title: 'No launchable apps reported',
          message:
              'Android returned an empty app list. Refresh to ask again; if '
              'the list stays empty, check this device’s app visibility '
              'settings.',
          icon: Icons.info_outline,
          action: PaperButton(label: 'Reload', onPressed: actions.refreshApps),
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
                    ? 'Android reported no launchable activities. Refresh to '
                          'ask again.'
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
              showIcons: launcher.showIcons,
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
    required this.showIcons,
  });

  final List<InstalledApp> items;
  final String query;
  final bool showIcons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<InstalledApp> favorites = ref.watch(favoriteAppsProvider);
    final List<InstalledApp> recents = ref.watch(recentAppsProvider);
    final bool showPinnedStrip = query.isEmpty && favorites.isNotEmpty;
    final Set<String> pinnedPackages = <String>{
      for (final InstalledApp app in favorites) app.packageName,
    };

    // The Pinned strip is a shortcut, not a second copy of the same rows. When
    // it is visible, the All apps list below starts with the unpinned remainder
    // of the one canonical order. Search still covers every visible app,
    // including pinned ones.
    final List<InstalledApp> rows = showPinnedStrip
        ? items
              .where(
                (InstalledApp app) => !pinnedPackages.contains(app.packageName),
              )
              .toList(growable: false)
        : items;

    final List<Widget> header = <Widget>[
      if (showPinnedStrip)
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
      if (query.isEmpty && rows.isNotEmpty)
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
      itemCount: header.length + rows.length,
      itemBuilder: (BuildContext context, int index) {
        if (index < header.length) return header[index];
        final int appIndex = index - header.length;
        final InstalledApp app = rows[appIndex];
        return _AppRow(
          app: app,
          showIcons: showIcons,
          showRule: appIndex != rows.length - 1,
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
