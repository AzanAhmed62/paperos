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

  /// Bumped when the stored envelope changes. Version 2 added the display
  /// profile; version 1 documents remain readable.
  static const int documentVersion = 2;

  AppSettings load() {
    final String? raw = _preferences.getString(settingsKey);
    if (raw == null || raw.isEmpty) return const AppSettings.defaults();
    try {
      return decode(raw);
    } catch (_) {
      // Persisted settings that no longer parse must not brick the app. Fall
      // back to defaults; the next write overwrites the bad payload.
      return const AppSettings.defaults();
    }
  }

  /// Parses a settings envelope without silently falling back to defaults.
  ///
  /// Backup restore uses this so a corrupt `settings.json` aborts the restore
  /// instead of replacing the user's preferences with defaults.
  AppSettings decode(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Settings are not a JSON object.');
    }
    final Object? version = decoded['version'];
    // Version 1 of the app wrote a bare settings object without an envelope.
    // Those documents remain readable; a version that is present must be a
    // supported integer. This is also what lets a legacy settings.json restore.
    if (version != null &&
        (version is! int || version < 1 || version > documentVersion)) {
      throw FormatException('Unsupported settings version: $version');
    }
    // A backup is untrusted input. Reject a section with the wrong shape
    // instead of silently replacing it with defaults, and turn the domain
    // model's casts into a FormatException the restore path already handles.
    for (final String section in const <String>[
      'appearance',
      'reader',
      'launcher',
      'home',
      'display',
    ]) {
      final Object? value = decoded[section];
      if (value != null && value is! Map) {
        throw FormatException('Settings section "$section" is not an object.');
      }
    }
    final Object? askOnExit = decoded['askOnExit'];
    if (askOnExit != null && askOnExit is! bool) {
      throw const FormatException('The askOnExit setting is not a boolean.');
    }
    try {
      return AppSettings.fromJson(decoded);
    } on TypeError {
      throw const FormatException(
        'Settings contain a value of the wrong type.',
      );
    }
  }

  String encode(AppSettings settings) => jsonEncode(_encode(settings));

  /// Exact settings document used by backup. Kept as an envelope so restore
  /// can distinguish a valid legacy document from arbitrary JSON.
  String exportJson(AppSettings settings) => encode(settings);

  Map<String, Object?> _encode(AppSettings settings) => <String, Object?>{
    'version': documentVersion,
    ...settings.toJson(),
  };

  Future<void> save(AppSettings settings) async {
    try {
      await _preferences.setString(settingsKey, encode(settings));
    } catch (error) {
      throw PaperException.storage(
        'PaperOS could not save your settings.',
        cause: error,
      );
    }
  }

  /// Validates and stores a settings document from a backup.
  Future<void> importJson(String raw) async {
    final AppSettings settings = decode(raw);
    await save(settings);
  }

  /// The raw stored value, used only for rollback snapshots.
  String? get rawValue => _preferences.getString(settingsKey);

  Future<void> restoreRaw(String? raw) async {
    if (raw == null) {
      await _preferences.remove(settingsKey);
    } else {
      await _preferences.setString(settingsKey, raw);
    }
  }
}
