import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/display/clock_tick.dart';
import '../../../core/display/display_profile.dart';
import '../../../core/errors/paper_exception.dart';
import '../../../core/platform/installed_app.dart';
import '../../../core/utils/date_format.dart';
import '../../../features/display/application/display_providers.dart';
import '../../../features/launcher/application/launcher_providers.dart';
import '../../../features/launcher/presentation/installed_app_icon.dart';
import '../../../features/library/application/library_providers.dart';
import '../../../features/library/data/library_service.dart';
import '../../../features/library/domain/document.dart';
import '../../../features/library/domain/library_models.dart';
import '../../../features/settings/application/settings_controller.dart';
import '../../../features/settings/domain/app_settings.dart';
import '../../../features/tasks/application/tasks_providers.dart';
import '../../../features/tasks/domain/task.dart';
import '../../../shared/widgets/paper_widgets.dart';
import '../../../theme/paper_palette.dart';
import '../../../theme/paper_space.dart';
import '../../../theme/paper_typography.dart';

/// Paper Home: the surface the user lands on when PaperOS is the launcher.
///
/// It answers four questions in a fixed order, most urgent first: what time is
/// it, what was I reading, what is due today, and what else is on the device.
/// It never shows content the user has not created, and it never invents a
/// suggestion — a home screen with nothing to say says so.
class PaperHomeScreen extends ConsumerWidget {
  const PaperHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HomeSettings home = ref.watch(settingsProvider).home;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: PaperSpace.xl),
          children: <Widget>[
            _HomeHeader(displayName: home.displayName),
            if (home.showClock)
              _ClockBlock(showDate: home.showDate, density: home.density),
            _QuickActions(showSearch: home.shows(HomeSection.search)),
            if (home.shows(HomeSection.continueReading))
              const _ContinueReadingSection(),
            if (home.shows(HomeSection.today)) const _TodaySection(),
            if (home.shows(HomeSection.recent)) const _RecentDocumentsSection(),
            const _FavoriteAppsSection(),
            const _LauncherSetupNotice(),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);

    // Search and Apps are deliberately not repeated here: the four-action row
    // immediately below is the single primary entry point for both. A header
    // icon would make the same action reachable twice within one thumb reach.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PaperSpace.gutter,
        PaperSpace.md,
        PaperSpace.gutter,
        0,
      ),
      child: Text(
        displayName,
        style: type.screenTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// A live clock whose cadence follows the display profile.
///
/// Standard rebuilds once a second, as before. E-Ink Friendly aligns a single
/// one-shot timer to the next minute boundary, so an idle home screen is not
/// repainting sixty times for a value that only changes every sixty seconds.
class _ClockBlock extends ConsumerStatefulWidget {
  const _ClockBlock({required this.showDate, required this.density});

  final bool showDate;
  final HomeDensity density;

  @override
  ConsumerState<_ClockBlock> createState() => _ClockBlockState();
}

class _ClockBlockState extends ConsumerState<_ClockBlock>
    with WidgetsBindingObserver {
  DateTime _now = DateTime.now();
  Timer? _timer;
  bool _minuteAligned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule(ref.read(displayPolicyProvider).alignClockToMinute);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _now = DateTime.now());
      _schedule(ref.read(displayPolicyProvider).alignClockToMinute);
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _schedule(bool minuteAligned) {
    _timer?.cancel();
    _minuteAligned = minuteAligned;
    final DisplayProfile profile = minuteAligned
        ? DisplayProfile.eink
        : DisplayProfile.standard;
    _timer = Timer(nextClockDelay(DateTime.now(), profile), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule(minuteAligned);
    });
  }

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);
    final bool minuteAligned = ref
        .watch(displayPolicyProvider)
        .alignClockToMinute;
    if (minuteAligned != _minuteAligned) {
      // A profile change can arrive during build. Arm the new cadence after
      // this frame so a timer is never created while the tree is locked.
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) _schedule(minuteAligned);
      });
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        PaperSpace.gutter,
        widget.density == HomeDensity.compact ? PaperSpace.lg : PaperSpace.xl,
        PaperSpace.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(formatClock(_now), style: type.clock),
          if (widget.showDate) ...<Widget>[
            const SizedBox(height: PaperSpace.xs),
            Text(formatLongDate(_now), style: type.date),
          ],
        ],
      ),
    );
  }
}

/// Four one-tap actions for the things a launcher is actually for.
///
/// They sit between the clock and the reading sections: visible without
/// scrolling, but not competing with the document the user came back to.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.showSearch});

  final bool showSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        child: SizedBox(
          height: 64,
          child: Row(
            children: <Widget>[
              if (showSearch) ...<Widget>[
                Expanded(
                  child: _QuickAction(
                    icon: Icons.search,
                    label: 'Search',
                    onTap: () => context.push(Routes.search),
                  ),
                ),
                _QuickDivider(palette: palette),
              ],
              Expanded(
                child: _QuickAction(
                  icon: Icons.grid_view_outlined,
                  label: 'Apps',
                  onTap: () => context.push(Routes.apps),
                ),
              ),
              _QuickDivider(palette: palette),
              Expanded(
                child: _QuickAction(
                  icon: Icons.note_add_outlined,
                  label: 'New note',
                  onTap: () => _newNote(context),
                ),
              ),
              _QuickDivider(palette: palette),
              Expanded(
                child: _QuickAction(
                  icon: Icons.add_task_outlined,
                  label: 'New task',
                  onTap: () => _newTask(context, ref),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _newNote(BuildContext context) {
    // The editor owns the draft-first lifecycle: an untouched new note never
    // reaches the database. Both Home and Notes use the same route.
    context.push(Routes.newNote);
  }

  Future<void> _newTask(BuildContext context, WidgetRef ref) async {
    final String? title = await showPaperTextPrompt(
      context,
      title: 'New task',
      label: 'What needs doing?',
      confirmLabel: 'Add',
    );
    if (title == null || !context.mounted) return;
    final DateTime now = DateTime.now();
    try {
      await ref
          .read(taskActionsProvider)
          .create(title, dueDate: DateTime(now.year, now.month, now.day));
    } on PaperException catch (error) {
      if (!context.mounted) return;
      PaperToast.show(context, error.message, icon: Icons.error_outline);
    }
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 20, color: palette.inkMuted),
          const SizedBox(height: PaperSpace.xs),
          Text(
            label,
            style: PaperTypography.of(context).caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _QuickDivider extends StatelessWidget {
  const _QuickDivider({required this.palette});

  final PaperPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: VerticalDivider(width: 1, thickness: 1, color: palette.rule),
    );
  }
}

/// The apps the user pinned, shown as a compact launcher row.
///
/// Nothing is shown when there are no pins: an empty "favourites" heading on a
/// home screen is a promise with nothing behind it. The drawer explains how to
/// pin, and the Launcher block below always opens it.
class _FavoriteAppsSection extends ConsumerWidget {
  const _FavoriteAppsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<InstalledApp> apps = ref.watch(favoriteAppsProvider);
    if (apps.isEmpty) return const SizedBox.shrink();

    final bool showIcons = ref.watch(
      settingsProvider.select(
        (AppSettings settings) => settings.launcher.showIcons,
      ),
    );

    return _SectionShell(
      label: 'Pinned',
      child: Wrap(
        spacing: PaperSpace.lg,
        runSpacing: PaperSpace.md,
        children: <Widget>[
          for (final InstalledApp app in apps)
            _HomeAppTile(app: app, showIcon: showIcons),
        ],
      ),
    );
  }
}

class _HomeAppTile extends ConsumerWidget {
  const _HomeAppTile({required this.app, required this.showIcon});

  final InstalledApp app;
  final bool showIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'Open ${app.label}',
      child: InkWell(
        onTap: () => _launch(context, ref),
        onLongPress: () =>
            ref.read(launcherActionsProvider).toggleFavorite(app),
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              InstalledAppIcon(app: app, size: 40, showIcon: showIcon),
              const SizedBox(height: PaperSpace.xs),
              Text(
                app.label.isEmpty ? app.packageName : app.label,
                style: PaperTypography.of(context).caption,
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

  Future<void> _launch(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(launcherActionsProvider).launch(app);
    } on PaperException catch (error) {
      if (!context.mounted) return;
      PaperToast.show(context, error.message, icon: Icons.error_outline);
    }
  }
}

class _SectionShell extends ConsumerWidget {
  const _SectionShell({
    required this.label,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String label;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HomeDensity density = ref.watch(
      settingsProvider.select((AppSettings settings) => settings.home.density),
    );
    final bool compact = density == HomeDensity.compact;

    return PaperSection(
      padding: EdgeInsets.fromLTRB(
        PaperSpace.gutter,
        compact ? PaperSpace.md : PaperSpace.xl,
        PaperSpace.gutter,
        compact ? PaperSpace.md : PaperSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PaperSectionLabel(
            label,
            trailing: actionLabel == null
                ? null
                : PaperTextAction(label: actionLabel!, onPressed: onAction!),
          ),
          const SizedBox(height: PaperSpace.md),
          child,
        ],
      ),
    );
  }
}

class _ContinueReadingSection extends ConsumerWidget {
  const _ContinueReadingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Document?> resume = ref.watch(continueReadingProvider);

    return _SectionShell(
      label: 'Continue reading',
      actionLabel: 'Library',
      onAction: () => context.go(Routes.library),
      child: resume.when(
        loading: () => const SizedBox(height: 84, child: PaperLoading()),
        error: (Object error, StackTrace stack) => Text(
          'Your reading position could not be loaded.',
          style: PaperTypography.of(context).bodyQuiet,
        ),
        data: (Document? document) {
          if (document == null) {
            return PaperEmptyState(
              title: 'Nothing to continue yet',
              message:
                  'Import a PDF or a text file. PaperOS remembers the page '
                  'you stop on and offers it here.',
              icon: Icons.auto_stories_outlined,
              action: PaperButton(
                label: 'Go to library',
                onPressed: () => context.go(Routes.library),
              ),
            );
          }
          return _ContinueCard(
            document: document,
            entry: LibraryService.present(document, DateTime.now()),
          );
        },
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.document, required this.entry});

  final Document document;
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);

    return InkWell(
      onTap: () => context.push(Routes.readerPath(document.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            entry.primary,
            style: type.heading,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: PaperSpace.xs),
          Text(
            entry.secondary,
            style: type.meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: PaperSpace.md),
          PaperProgressBar(value: document.progressFraction, showLabel: true),
          if (entry.showProgress) ...<Widget>[
            const SizedBox(height: PaperSpace.sm),
            Text(entry.progressLine, style: type.caption),
          ],
        ],
      ),
    );
  }
}

class _TodaySection extends ConsumerWidget {
  const _TodaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Task>> tasks = ref.watch(todayTasksProvider);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    return _SectionShell(
      label: formatLongDate(today),
      actionLabel: 'Add',
      onAction: () => _promptForTask(context, ref, today),
      child: tasks.when(
        loading: () => const SizedBox(height: 72, child: PaperLoading()),
        error: (Object error, StackTrace stack) => Text(
          'Your tasks could not be loaded.',
          style: PaperTypography.of(context).bodyQuiet,
        ),
        data: (List<Task> items) {
          if (items.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Nothing scheduled for today.',
                  style: PaperTypography.of(context).bodyQuiet,
                ),
                const SizedBox(height: PaperSpace.md),
                PaperButton(
                  label: 'Add a task',
                  icon: Icons.add,
                  onPressed: () => _promptForTask(context, ref, today),
                ),
              ],
            );
          }
          return Column(
            children: <Widget>[
              for (final Task task in items.take(6))
                _TaskRow(task: task, selectedDay: today),
              if (items.length > 6)
                Align(
                  alignment: Alignment.centerLeft,
                  child: PaperTextAction(
                    label: '${items.length - 6} more',
                    onPressed: () => context.push(Routes.tasks),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _promptForTask(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
  ) async {
    final String? title = await showPaperTextPrompt(
      context,
      title: 'New task',
      label: 'What needs doing?',
      confirmLabel: 'Add',
    );
    if (title == null || !context.mounted) return;
    await ref.read(taskActionsProvider).create(title, dueDate: day);
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task, required this.selectedDay});

  final Task task;
  final DateTime selectedDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PaperTypography type = PaperTypography.of(context);
    final PaperPalette palette = paperPalette(context);
    final bool overdue = task.isOverdueOn(selectedDay);

    return InkWell(
      onTap: () => ref.read(taskActionsProvider).setDone(task, !task.isDone),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: PaperSpace.sm + PaperSpace.xs,
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: task.isDone,
                onChanged: (bool? value) =>
                    ref.read(taskActionsProvider).setDone(task, value ?? false),
                side: BorderSide(color: palette.ruleStrong, width: 1.2),
                fillColor: WidgetStatePropertyAll<Color>(palette.inverseCanvas),
                checkColor: palette.inverseInk,
                shape: const RoundedRectangleBorder(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: PaperSpace.md),
            Expanded(
              child: Text(
                task.title,
                style: type.body.copyWith(
                  decoration: task.isDone ? TextDecoration.lineThrough : null,
                  color: task.isDone
                      ? palette.inkFaint
                      : (overdue ? palette.ink : palette.ink),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentDocumentsSection extends ConsumerWidget {
  const _RecentDocumentsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Document>> documents = ref.watch(
      recentDocumentsProvider,
    );
    final DateTime now = DateTime.now();

    return _SectionShell(
      label: 'Recent',
      actionLabel: 'Search',
      onAction: () => context.push(Routes.search),
      child: documents.when(
        loading: () => const SizedBox(height: 64, child: PaperLoading()),
        error: (Object error, StackTrace stack) => Text(
          'Your documents could not be loaded.',
          style: PaperTypography.of(context).bodyQuiet,
        ),
        data: (List<Document> items) {
          if (items.isEmpty) {
            return Text(
              'No documents have been opened yet.',
              style: PaperTypography.of(context).bodyQuiet,
            );
          }
          return Column(
            children: <Widget>[
              for (final Document document in items)
                PaperListTile(
                  title: document.title,
                  subtitle: LibraryService.present(
                    document,
                    now,
                    showByteSize: false,
                  ).secondary,
                  dense: true,
                  trailing: document.progressFraction > 0
                      ? SizedBox(
                          width: 40,
                          child: PaperProgressBar(
                            value: document.progressFraction,
                          ),
                        )
                      : null,
                  onTap: () => context.push(Routes.readerPath(document.id)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A compact, contextual launcher-setup message.
///
/// PaperOS is a launcher, but Paper Home is not a setup wizard. This block is
/// shown only while Android reports that PaperOS does not hold the HOME role.
/// Once the role is held it disappears entirely; Settings remains the
/// authoritative place for launcher configuration. The app drawer itself has
/// exactly one Home entry point: the Apps action in the four-action row.
class _LauncherSetupNotice extends ConsumerWidget {
  const _LauncherSetupNotice();

  Future<void> _requestHomeRole(BuildContext context, WidgetRef ref) async {
    final LauncherActions actions = ref.read(launcherActionsProvider);
    try {
      final HomeRoleStatus status = await actions.requestHomeRole();
      if (!context.mounted) return;
      switch (status.flow) {
        case HomeRoleFlow.roleRequest:
          PaperToast.show(
            context,
            status.isHomeApp
                ? 'PaperOS is now your home app.'
                : 'Home app not set. You can do it in system settings.',
            icon: Icons.home_outlined,
          );
        case HomeRoleFlow.settings:
          await actions.openHomeSettings();
        case HomeRoleFlow.already:
          PaperToast.show(
            context,
            'PaperOS is already your home app.',
            icon: Icons.home_outlined,
          );
        case HomeRoleFlow.unavailable:
          PaperToast.show(
            context,
            'This Android version cannot assign the home role from an app.',
            icon: Icons.info_outline,
          );
      }
    } on PaperException catch (error) {
      if (!context.mounted) return;
      PaperToast.show(context, error.message, icon: Icons.info_outline);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<bool> role = ref.watch(homeRoleProvider);
    // Loading or a failed role query is not evidence that setup is needed.
    // Showing nothing avoids a false "not your home app" flash on every start.
    if (role.value != false) return const SizedBox.shrink();

    final PaperTypography type = PaperTypography.of(context);
    final PaperPalette palette = paperPalette(context);
    final HomeDensity density = ref.watch(
      settingsProvider.select((AppSettings settings) => settings.home.density),
    );

    return PaperSection(
      padding: EdgeInsets.fromLTRB(
        PaperSpace.gutter,
        density == HomeDensity.compact ? PaperSpace.md : PaperSpace.lg,
        PaperSpace.gutter,
        PaperSpace.xl,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: palette.rule)),
        child: Padding(
          padding: const EdgeInsets.all(PaperSpace.md),
          child: Row(
            children: <Widget>[
              Icon(Icons.home_outlined, size: 20, color: palette.inkMuted),
              const SizedBox(width: PaperSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Make PaperOS your home app', style: type.bodyStrong),
                    const SizedBox(height: PaperSpace.xs),
                    Text(
                      'Pressing Home returns to this screen.',
                      style: type.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PaperSpace.sm),
              PaperTextAction(
                label: 'Set up',
                onPressed: () => _requestHomeRole(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
