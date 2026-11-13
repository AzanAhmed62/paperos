import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/display/display_profile.dart';
import '../../../theme/paper_palette.dart';
import '../data/settings_repository.dart';
import '../domain/app_settings.dart';

/// Holds [AppSettings] in memory and persists every change.
///
/// A single [Notifier] rather than one provider per preference: PaperOS has one
/// settings document, every screen reads it, and a single source removes any
/// chance of two screens disagreeing about the current theme.
class SettingsController extends Notifier<AppSettings> {
  SettingsRepository get _repository => ref.read(settingsRepositoryProvider);

  @override
  AppSettings build() => _repository.load();

  Future<void> _write(AppSettings next) async {
    state = next;
    await _repository.save(next);
  }

  Future<void> setPaperStyle(PaperStyle style) => _write(
    state.copyWith(appearance: state.appearance.copyWith(style: style)),
  );

  Future<void> setTextScale(double scale) => _write(
    state.copyWith(appearance: state.appearance.copyWith(textScale: scale)),
  );

  Future<void> setSerifReading(bool enabled) => _write(
    state.copyWith(
      appearance: state.appearance.copyWith(serifReading: enabled),
    ),
  );

  Future<void> setDisplayProfile(DisplayProfile profile) =>
      _write(state.copyWith(display: state.display.copyWith(profile: profile)));

  /// Replaces in-memory state after a backup restore wrote the repository
  /// directly. Every screen watching this provider updates immediately.
  void reload() {
    state = _repository.load();
  }

  Future<void> setReaderFontSize(double size) =>
      _write(state.copyWith(reader: state.reader.copyWith(fontSize: size)));

  Future<void> setReaderLineHeight(double height) =>
      _write(state.copyWith(reader: state.reader.copyWith(lineHeight: height)));

  Future<void> setReaderMargin(double margin) =>
      _write(state.copyWith(reader: state.reader.copyWith(margin: margin)));

  Future<void> setTurnMode(PageTurnMode mode) =>
      _write(state.copyWith(reader: state.reader.copyWith(turnMode: mode)));

  Future<void> setReaderFlow(ReaderFlow flow) =>
      _write(state.copyWith(reader: state.reader.copyWith(flow: flow)));

  Future<void> setShowPageNumbers(bool show) => _write(
    state.copyWith(reader: state.reader.copyWith(showPageNumbers: show)),
  );

  Future<void> setKeepScreenOn(bool keep) =>
      _write(state.copyWith(reader: state.reader.copyWith(keepScreenOn: keep)));

  Future<void> setShowAppIcons(bool show) => _write(
    state.copyWith(launcher: state.launcher.copyWith(showIcons: show)),
  );

  Future<void> setShowSystemApps(bool show) => _write(
    state.copyWith(launcher: state.launcher.copyWith(showSystemApps: show)),
  );

  Future<void> setShowRecents(bool show) => _write(
    state.copyWith(launcher: state.launcher.copyWith(showRecents: show)),
  );

  /// Moves [packageName] to the front of the recents strip.
  ///
  /// Bounded by [LauncherSettings.maxRecents]. The list is intentionally not a
  /// launch history with timestamps: the drawer only needs "what did I use
  /// lately", and storing more would turn a preference into a usage log.
  Future<void> recordRecentApp(String packageName) {
    final List<String> current = List<String>.from(
      state.launcher.recentPackages,
    )..remove(packageName);
    return _write(
      state.copyWith(
        launcher: state.launcher.copyWith(
          recentPackages: <String>[
            packageName,
            ...current,
          ].take(LauncherSettings.maxRecents).toList(growable: false),
        ),
      ),
    );
  }

  Future<void> clearRecentApps() => _write(
    state.copyWith(
      launcher: state.launcher.copyWith(recentPackages: const <String>[]),
    ),
  );

  Future<void> setShowDate(bool show) =>
      _write(state.copyWith(home: state.home.copyWith(showDate: show)));

  Future<void> setHomeDensity(HomeDensity density) =>
      _write(state.copyWith(home: state.home.copyWith(density: density)));

  Future<void> setHomeSectionVisible(HomeSection section, bool visible) {
    final Set<HomeSection> hidden = Set<HomeSection>.from(
      state.home.hiddenSections,
    );
    if (visible) {
      hidden.remove(section);
    } else {
      hidden.add(section);
    }
    return _write(
      state.copyWith(home: state.home.copyWith(hiddenSections: hidden)),
    );
  }

  Future<void> setShowClock(bool show) =>
      _write(state.copyWith(home: state.home.copyWith(showClock: show)));

  Future<void> setAskOnExit(bool ask) => _write(state.copyWith(askOnExit: ask));

  Future<void> setFavorites(List<String> packages) => _write(
    state.copyWith(
      launcher: state.launcher.copyWith(favoritePackages: packages),
    ),
  );

  /// Adds or removes a package from the pinned list, keeping the newest pin
  /// first.
  Future<void> toggleFavorite(String packageName) {
    final List<String> current = List<String>.from(
      state.launcher.favoritePackages,
    );
    if (current.remove(packageName)) {
      return setFavorites(current);
    }
    return setFavorites(<String>[packageName, ...current]);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
