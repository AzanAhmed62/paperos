import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/features/settings/data/settings_repository.dart';
import 'package:paperos/features/settings/domain/app_settings.dart';
import 'package:paperos/theme/paper_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  late SettingsRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
    repository = SettingsRepository(preferences);
  });

  test('returns defaults when nothing has been saved', () {
    final AppSettings settings = repository.load();

    expect(settings.appearance.style, PaperStyle.white);
    expect(settings.reader.turnMode, PageTurnMode.tap);
    expect(settings.reader.fontSize, 1.0);
    expect(settings.launcher.favoritePackages, isEmpty);
    expect(settings.launcher.recentPackages, isEmpty);
    expect(settings.launcher.showRecents, isTrue);
    expect(settings.home.showDate, isTrue);
    expect(settings.home.density, HomeDensity.comfortable);
    expect(settings.askOnExit, isTrue);
  });

  test('round-trips a fully customised settings object', () async {
    final AppSettings custom = const AppSettings().copyWith(
      appearance: const AppearanceSettings(
        style: PaperStyle.warm,
        textScale: 1.25,
        serifReading: false,
      ),
      reader: const ReaderSettings(
        fontSize: 1.3,
        lineHeight: 1.8,
        margin: 32,
        turnMode: PageTurnMode.swipe,
        showPageNumbers: false,
        keepScreenOn: true,
      ),
      launcher: const LauncherSettings(
        showIcons: false,
        showSystemApps: true,
        showRecents: false,
        favoritePackages: <String>['com.example.reader', 'org.mozilla.firefox'],
        recentPackages: <String>['com.example.notes', 'com.example.reader'],
      ),
      home: const HomeSettings(
        hiddenSections: <HomeSection>{HomeSection.today, HomeSection.search},
        showClock: false,
        showDate: false,
        density: HomeDensity.compact,
      ),
      askOnExit: false,
    );

    await repository.save(custom);

    // A second repository over the same preferences proves the value really
    // went through JSON and came back, not just through an in-memory object.
    final AppSettings loaded = SettingsRepository(preferences).load();

    expect(loaded.appearance.style, PaperStyle.warm);
    expect(loaded.appearance.textScale, 1.25);
    expect(loaded.appearance.serifReading, isFalse);
    expect(loaded.reader.fontSize, 1.3);
    expect(loaded.reader.lineHeight, 1.8);
    expect(loaded.reader.margin, 32);
    expect(loaded.reader.turnMode, PageTurnMode.swipe);
    expect(loaded.reader.showPageNumbers, isFalse);
    expect(loaded.reader.keepScreenOn, isTrue);
    expect(loaded.launcher.showIcons, isFalse);
    expect(loaded.launcher.showSystemApps, isTrue);
    expect(loaded.launcher.showRecents, isFalse);
    expect(loaded.launcher.favoritePackages, <String>[
      'com.example.reader',
      'org.mozilla.firefox',
    ]);
    expect(loaded.launcher.recentPackages, <String>[
      'com.example.notes',
      'com.example.reader',
    ]);
    expect(loaded.home.hiddenSections, <HomeSection>{
      HomeSection.today,
      HomeSection.search,
    });
    expect(loaded.home.showClock, isFalse);
    expect(loaded.home.showDate, isFalse);
    expect(loaded.home.density, HomeDensity.compact);
    expect(loaded.askOnExit, isFalse);
  });

  test('falls back to defaults when the stored payload is corrupt', () async {
    await preferences.setString(SettingsRepository.settingsKey, 'not json {');

    final AppSettings settings = repository.load();

    expect(settings.appearance.style, PaperStyle.white);
    expect(settings.reader.turnMode, PageTurnMode.tap);
  });

  test('tolerates a well-formed but partial payload', () async {
    await preferences.setString(
      SettingsRepository.settingsKey,
      jsonEncode(<String, Object?>{
        'version': 1,
        'reader': <String, Object?>{'fontSize': 1.4},
      }),
    );

    final AppSettings settings = repository.load();

    expect(settings.reader.fontSize, 1.4);
    // Untouched sections keep their defaults rather than going null.
    expect(settings.appearance.style, PaperStyle.white);
    expect(settings.launcher.favoritePackages, isEmpty);
    expect(settings.home.showClock, isTrue);
  });

  test('ignores an unknown enum value instead of throwing', () async {
    await preferences.setString(
      SettingsRepository.settingsKey,
      jsonEncode(<String, Object?>{
        'reader': <String, Object?>{'turnMode': 'telepathy'},
      }),
    );

    expect(repository.load().reader.turnMode, PageTurnMode.tap);
  });

  test('drops non-string entries from the favourites list', () async {
    await preferences.setString(
      SettingsRepository.settingsKey,
      jsonEncode(<String, Object?>{
        'launcher': <String, Object?>{
          'favoritePackages': <Object?>['com.ok', 42, null, 'com.also.ok'],
        },
      }),
    );

    expect(repository.load().launcher.favoritePackages, <String>[
      'com.ok',
      'com.also.ok',
    ]);
  });

  test('decode rejects a section with the wrong shape', () {
    expect(
      () => repository.decode(
        jsonEncode(<String, Object?>{'appearance': <Object?>[]}),
      ),
      throwsFormatException,
    );
  });

  test('decode turns wrong field types into a FormatException', () {
    expect(
      () => repository.decode(
        jsonEncode(<String, Object?>{
          'reader': <String, Object?>{'fontSize': 'huge'},
        }),
      ),
      throwsFormatException,
    );
    expect(
      () =>
          repository.decode(jsonEncode(<String, Object?>{'askOnExit': 'yes'})),
      throwsFormatException,
    );
  });

  test('a later save overwrites an earlier one', () async {
    await repository.save(const AppSettings());
    await repository.save(
      const AppSettings().copyWith(
        appearance: const AppearanceSettings(textScale: 0.9),
      ),
    );

    expect(repository.load().appearance.textScale, 0.9);
  });
}
