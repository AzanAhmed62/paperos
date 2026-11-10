import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../config/app_config.dart';
import '../../../core/display/display_profile.dart';
import '../../../core/errors/paper_exception.dart';
import '../../../core/platform/installed_app.dart';
import '../../../shared/widgets/paper_widgets.dart';
import '../../../theme/paper_palette.dart';
import '../../../theme/paper_space.dart';
import '../../../theme/paper_typography.dart';
import '../../backup/presentation/backup_section.dart';
import '../../display/application/display_providers.dart';
import '../../launcher/application/launcher_providers.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/app_settings.dart';

/// Settings.
///
/// Every preference is a real switch, an actual stored value, and takes effect
/// immediately. There is no "apply" button, because there is nothing to apply:
/// a setting the user cannot see the effect of is a setting they will not trust.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);
    final SettingsController controller = ref.read(settingsProvider.notifier);
    final PaperPalette palette = paperPalette(context);

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: const PaperTopBar(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: PaperSpace.xxxl),
        children: <Widget>[
          _Section(
            title: 'Paper',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PaperSpace.gutter,
                  PaperSpace.md,
                  PaperSpace.gutter,
                  PaperSpace.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Paper style',
                      style: PaperTypography.of(context).body,
                    ),
                    const SizedBox(height: PaperSpace.sm),
                    Row(
                      children: <Widget>[
                        for (final PaperStyle style in PaperStyle.values)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: PaperSpace.sm,
                            ),
                            child: _Swatch(
                              style: style,
                              selected: settings.appearance.style == style,
                              onTap: () => controller.setPaperStyle(style),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: PaperSpace.sm),
                    Text(
                      'Warm is easier on the eyes in daylight. Ink is a dark '
                      'page for reading at night.',
                      style: PaperTypography.of(context).caption,
                    ),
                  ],
                ),
              ),
              const PaperRule(inset: PaperSpace.gutter),
              PaperStepper(
                label: 'Interface text size',
                display: '${(settings.appearance.textScale * 100).round()}%',
                canDecrease: settings.appearance.textScale > 0.9,
                canIncrease: settings.appearance.textScale < 1.4,
                onDecrease: () => controller.setTextScale(
                  settings.appearance.textScale - 0.05,
                ),
                onIncrease: () => controller.setTextScale(
                  settings.appearance.textScale + 0.05,
                ),
              ),
              const PaperRule(inset: PaperSpace.gutter),
              PaperSettingRow(
                label: 'Serif reading face',
                subtitle:
                    'Use the bundled serif in the reader and on Paper Home.',
                trailing: PaperSwitch(
                  value: settings.appearance.serifReading,
                  onChanged: controller.setSerifReading,
                ),
              ),
            ],
          ),
          const _DisplaySection(),
          _Section(
            title: 'Reading',
            children: <Widget>[
              PaperStepper(
                label: 'Reader text size',
                display: '${(settings.reader.fontSize * 100).round()}%',
                canDecrease: settings.reader.fontSize > 0.85,
                canIncrease: settings.reader.fontSize < 1.6,
                onDecrease: () => controller.setReaderFontSize(
                  settings.reader.fontSize - 0.05,
                ),
                onIncrease: () => controller.setReaderFontSize(
                  settings.reader.fontSize + 0.05,
                ),
              ),
              const PaperRule(inset: PaperSpace.gutter),
              PaperStepper(
                label: 'Line spacing',
                display: settings.reader.lineHeight.toStringAsFixed(2),
                canDecrease: settings.reader.lineHeight > 1.25,
                canIncrease: settings.reader.lineHeight < 2.1,
                onDecrease: () => controller.setReaderLineHeight(
                  settings.reader.lineHeight - 0.05,
                ),
                onIncrease: () => controller.setReaderLineHeight(
                  settings.reader.lineHeight + 0.05,
                ),
              ),
              const PaperRule(inset: PaperSpace.gutter),
              PaperSettingRow(
                label: 'Page turns',
                trailing: Wrap(
                  spacing: PaperSpace.xs,
                  children: <Widget>[
                    for (final PageTurnMode mode in PageTurnMode.values)
                      PaperChip(
                        label: mode.label,
                        selected: settings.reader.turnMode == mode,
                        onTap: () => controller.setTurnMode(mode),
                      ),
                  ],
                ),
              ),
              const PaperRule(inset: PaperSpace.gutter),
              PaperSettingRow(
                label: 'Keep the screen on',
                subtitle: 'While a document is open in the reader.',
                trailing: PaperSwitch(
                  value: settings.reader.keepScreenOn,
                  onChanged: controller.setKeepScreenOn,
                ),
              ),
            ],
          ),
          _Section(
            title: 'Paper Home',
            children: <Widget>[
              PaperSettingRow(
                label: 'Clock',
                subtitle: 'A live 24-hour clock at the top of Paper Home.',
                trailing: PaperSwitch(
                  value: settings.home.showClock,
                  onChanged: controller.setShowClock,
                ),
              ),
              const PaperRule(inset: PaperSpace.gutter),
              for (final HomeSection section in HomeSection.values) ...<Widget>[
                PaperSettingRow(
                  label: section.label,
                  trailing: PaperSwitch(
                    value: !settings.home.hiddenSections.contains(section),
                    onChanged: (bool visible) =>
                        controller.setHomeSectionVisible(section, visible),
                  ),
                ),
                if (section != HomeSection.values.last)
                  const PaperRule(inset: PaperSpace.gutter),
              ],
            ],
          ),
          _Section(
            title: 'App drawer',
            children: <Widget>[
              PaperSettingRow(
                label: 'Show system apps',
                subtitle: 'Includes preinstalled apps such as Settings.',
                trailing: PaperSwitch(
                  value: settings.launcher.showSystemApps,
                  onChanged: controller.setShowSystemApps,
                ),
              ),
              const PaperRule(inset: PaperSpace.gutter),
              const _FavouritesEditor(),
            ],
          ),
          const BackupSection(),
          const _StorageSection(),
          const _AboutSection(),
        ],
      ),
    );
  }
}

class _DisplaySection extends ConsumerWidget {
  const _DisplaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PaperTypography type = PaperTypography.of(context);
    final AppSettings settings = ref.watch(settingsProvider);
    final SettingsController controller = ref.read(settingsProvider.notifier);
    final DisplayProfile profile = settings.display.profile;
    final policy = ref.watch(displayPolicyProvider);

    return _Section(
      title: 'Display',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PaperSpace.gutter,
            PaperSpace.md,
            PaperSpace.gutter,
            PaperSpace.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Display profile', style: type.body),
              const SizedBox(height: PaperSpace.xs),
              Text(policy.description, style: type.caption),
              const SizedBox(height: PaperSpace.sm),
              Wrap(
                spacing: PaperSpace.sm,
                runSpacing: PaperSpace.xs,
                children: <Widget>[
                  for (final DisplayProfile value in DisplayProfile.values)
                    PaperChip(
                      label: value.label,
                      selected: profile == value,
                      onTap: () => controller.setDisplayProfile(value),
                    ),
                ],
              ),
            ],
          ),
        ),
        const PaperRule(inset: PaperSpace.gutter),
        PaperSettingRow(
          label: 'Panel capability',
          subtitle: policy.capabilities.summary,
        ),
        const SizedBox(height: PaperSpace.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PaperSpace.gutter),
          child: Text(
            'E-Ink Friendly changes real behaviour: navigation is instant, the '
            'clock updates on the minute, controls are larger, contrast is '
            'stronger, and the reader uses pages and tap zones only. PaperOS '
            'does not send undocumented vendor refresh commands.',
            style: type.caption,
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PaperSpace.gutter,
            PaperSpace.xl,
            PaperSpace.gutter,
            PaperSpace.sm,
          ),
          child: Text(title, style: PaperTypography.of(context).sectionLabel),
        ),
        ...children,
        const SizedBox(height: PaperSpace.lg),
      ],
    );
  }
}

/// A paper-style swatch. Selecting one re-themes the whole app immediately,
/// which is the only way to make the choice obvious.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final PaperStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = PaperPalette.of(style);

    return Semantics(
      button: true,
      selected: selected,
      label: style.label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: palette.canvas,
            border: Border.all(
              color: selected ? palette.ink : palette.rule,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Center(
            child: Text(
              'Aa',
              style: TextStyle(
                fontFamily: style == PaperStyle.white
                    ? null
                    : kPaperSerifFamily,
                fontSize: 15,
                color: palette.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pinned-app list, in order.
class _FavouritesEditor extends ConsumerWidget {
  const _FavouritesEditor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<String> favorites = ref
        .watch(settingsProvider)
        .launcher
        .favoritePackages;

    return PaperSettingRow(
      label: 'Pinned apps',
      subtitle: favorites.isEmpty
          ? 'None. Apps are listed alphabetically.'
          : '${favorites.length} pinned, in this order.',
      onTap: () => _edit(context, ref),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final SettingsController controller = ref.read(settingsProvider.notifier);
    final List<String> current = List<String>.of(
      ref.read(settingsProvider).launcher.favoritePackages,
    );
    final PaperPalette palette = paperPalette(context);

    // Captured before the await so no BuildContext crosses the gap.
    final Future<List<InstalledApp>> appsFuture = ref.read(
      installedAppsProvider.future,
    );
    final List<InstalledApp> apps;
    try {
      apps = await appsFuture;
    } on PaperException catch (error) {
      if (context.mounted) {
        PaperToast.show(context, error.message, icon: Icons.info_outline);
      }
      return;
    } catch (_) {
      if (context.mounted) {
        PaperToast.show(
          context,
          'Installed apps could not be listed on this device.',
          icon: Icons.info_outline,
        );
      }
      return;
    }
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: paperModalAnimationStyle(context),
      isScrollControlled: true,
      backgroundColor: palette.canvas,
      barrierColor: palette.ink.withValues(alpha: 0.32),
      shape: const RoundedRectangleBorder(),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PaperSpace.gutter,
                      PaperSpace.lg,
                      PaperSpace.gutter,
                      PaperSpace.sm,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Pinned apps',
                            style: PaperTypography.of(context).heading,
                          ),
                        ),
                        PaperButton(
                          label: 'Done',
                          onPressed: () {
                            controller.setFavorites(current);
                            Navigator.of(sheetContext).pop();
                          },
                        ),
                      ],
                    ),
                  ),
                  const PaperRule(strong: true),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: apps.length,
                      itemBuilder: (BuildContext context, int index) {
                        final InstalledApp app = apps[index];
                        final int pinIndex = current.indexOf(app.packageName);
                        final bool pinned = pinIndex >= 0;
                        return PaperListTile(
                          title: app.label.isEmpty
                              ? app.packageName
                              : app.label,
                          subtitle: pinned
                              ? 'Pinned ${pinIndex + 1}'
                              : app.packageName,
                          trailing: IconButton(
                            onPressed: () => setSheetState(() {
                              if (pinned) {
                                current.removeAt(pinIndex);
                              } else {
                                current.add(app.packageName);
                              }
                            }),
                            icon: Icon(
                              pinned ? Icons.push_pin : Icons.push_pin_outlined,
                              size: 18,
                            ),
                            tooltip: pinned ? 'Unpin' : 'Pin to top',
                          ),
                          onTap: () => setSheetState(() {
                            if (pinned) {
                              current.removeAt(pinIndex);
                            } else {
                              current.add(app.packageName);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: PaperSpace.sm),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// What PaperOS is storing and how to clear it.
class _StorageSection extends ConsumerStatefulWidget {
  const _StorageSection();

  @override
  ConsumerState<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends ConsumerState<_StorageSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);

    return _Section(
      title: 'Storage',
      children: <Widget>[
        const PaperSettingRow(
          label: 'Where files live',
          subtitle:
              'Imports are copied into PaperOS private storage. Nothing is '
              'written to shared storage, and no storage permission is held.',
        ),
        const PaperRule(inset: PaperSpace.gutter),
        PaperSettingRow(
          label: 'Remove every document',
          subtitle:
              'Deletes the copies PaperOS made and all reading progress. '
              'Notes and tasks are kept.',
          trailing: _busy ? const PaperProgress() : null,
          onTap: _busy ? null : _clearLibrary,
        ),
        const SizedBox(height: PaperSpace.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PaperSpace.gutter),
          child: Text(
            'PaperOS keeps no network code, no analytics, and no account. '
            'Uninstalling removes everything it stored.',
            style: type.caption,
          ),
        ),
      ],
    );
  }

  Future<void> _clearLibrary() async {
    final bool confirmed = await confirmDestructiveAction(
      context,
      title: 'Remove every document?',
      message:
          'All imported files, reading progress and bookmarks created by '
          'PaperOS will be deleted from this device. Notes and tasks are not '
          'affected.',
      confirmLabel: 'Remove all',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await ref.read(libraryServiceProvider).removeAll();
      if (mounted) {
        PaperToast.show(
          context,
          'Library cleared',
          icon: Icons.delete_sweep_outlined,
        );
      }
    } on PaperException catch (error) {
      if (mounted) {
        PaperToast.show(context, error.message, icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'About',
      children: <Widget>[
        PaperSettingRow(
          label: 'Version',
          subtitle:
              '${PaperConfig.appName} ${PaperConfig.versionLabel} · '
              'schema v${PaperConfig.databaseVersion}',
        ),
        const PaperRule(inset: PaperSpace.gutter),
        const PaperSettingRow(
          label: 'Reading faces',
          subtitle:
              'Noto Serif, SIL Open Font License 1.1. Bundled in the '
              'app so the reader looks the same offline.',
        ),
      ],
    );
  }
}
