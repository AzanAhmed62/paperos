import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/paper_exception.dart';
import '../domain/app_settings.dart';

/// Reads and writes [AppSettings] as a single JSON document.
///
/// One key, one read, one write. Settings are read on every cold start (they
/// decide the theme) and written on every change, so a single synchronous
/// value beats a key-per-setting schema.
class SettingsRepository {
  SettingsRepository(this._preferences);

  final SharedPreferences _preferences;

  static const String settingsKey = 'paperos.settings.v1';

  AppSettings load() {
    final String? raw = _preferences.getString(settingsKey);
    if (raw == null || raw.isEmpty) return const AppSettings.defaults();
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return const AppSettings.defaults();
      }
      return AppSettings(
        appearance: AppearanceSettings.fromJson(
          _section(decoded, 'appearance'),
        ),
        reader: ReaderSettings.fromJson(_section(decoded, 'reader')),
        launcher: LauncherSettings.fromJson(_section(decoded, 'launcher')),
        home: HomeSettings.fromJson(_section(decoded, 'home')),
        askOnExit: (decoded['askOnExit'] as bool?) ?? true,
      );
    } catch (_) {
      // Persisted settings that no longer parse must not brick the app. Fall
      // back to defaults; the next write overwrites the bad payload.
      return const AppSettings.defaults();
    }
  }

  static Map<String, Object?> _section(
    Map<String, Object?> source,
    String key,
  ) {
    final Object? value = source[key];
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.cast<String, Object?>();
    return const <String, Object?>{};
  }

  Map<String, Object?> _encode(AppSettings settings) => <String, Object?>{
    'version': 1,
    'appearance': settings.appearance.toJson(),
    'reader': settings.reader.toJson(),
    'launcher': settings.launcher.toJson(),
    'home': settings.home.toJson(),
    'askOnExit': settings.askOnExit,
  };

  Future<void> save(AppSettings settings) async {
    try {
      await _preferences.setString(settingsKey, jsonEncode(_encode(settings)));
    } catch (error) {
      throw PaperException.storage(
        'PaperOS could not save your settings.',
        cause: error,
      );
    }
  }
}
