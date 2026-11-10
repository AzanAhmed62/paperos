import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/display/clock_tick.dart';
import 'package:paperos/core/display/display_capability_service.dart';
import 'package:paperos/core/display/display_policy.dart';
import 'package:paperos/core/display/display_profile.dart';
import 'package:paperos/features/display/application/reader_display_settings.dart';
import 'package:paperos/features/settings/data/settings_repository.dart';
import 'package:paperos/features/settings/domain/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DisplayProfile', () {
    test('parses stable identifiers and falls back to standard', () {
      expect(DisplayProfile.fromId('eink'), DisplayProfile.eink);
      expect(DisplayProfile.fromId('standard'), DisplayProfile.standard);
      expect(DisplayProfile.fromId('unknown'), DisplayProfile.standard);
      expect(DisplayProfile.fromId(null), DisplayProfile.standard);
      expect(DisplayProfile.eink.isEink, isTrue);
      expect(DisplayProfile.standard.isEink, isFalse);
    });
  });

  group('DisplayCapabilities', () {
    test(
      'the shipped service is conservative and never claims flash support',
      () {
        final DisplayCapabilities capabilities =
            const ConservativeDisplayCapabilityService().capabilities();
        expect(capabilities.isEinkPanel, isFalse);
        expect(capabilities.supportsHardwareRefresh, isFalse);
        expect(capabilities.vendorName, isNull);
        expect(capabilities.summary, contains('Software-only'));
      },
    );

    test('hardware refresh is only exposed when a vendor API is attached', () {
      const DisplayPolicy noApi = DisplayPolicy(
        profile: DisplayProfile.eink,
        capabilities: DisplayCapabilities(
          isEinkPanel: true,
          vendorName: 'Example',
        ),
      );
      expect(noApi.hardwareRefreshAvailable, isFalse);

      const DisplayPolicy withApi = DisplayPolicy(
        profile: DisplayProfile.eink,
        capabilities: DisplayCapabilities(
          isEinkPanel: true,
          supportsHardwareRefresh: true,
          vendorName: 'Example',
        ),
      );
      expect(withApi.hardwareRefreshAvailable, isTrue);
      expect(withApi.capabilities.summary, contains('Example'));
    });
  });

  group('DisplayPolicy', () {
    test('standard keeps the historic, animated presentation', () {
      const DisplayPolicy policy = DisplayPolicy.standard;
      expect(policy.reduceMotion, isFalse);
      expect(policy.navigationDuration, const Duration(milliseconds: 220));
      expect(policy.chromeAnimationDuration, const Duration(milliseconds: 160));
      expect(policy.alignClockToMinute, isFalse);
      expect(policy.forcePagedReader, isFalse);
      expect(policy.forceTapPageTurns, isFalse);
      expect(policy.autoHideReaderChrome, isTrue);
      expect(policy.largeTargets, isFalse);
      expect(policy.highContrast, isFalse);
      expect(policy.selectionOpacity, 0.20);
      expect(policy.readerFontScale, 1);
      expect(policy.readerLineHeightDelta, 0);
      expect(policy.readerMarginScale, 1);
      expect(policy.pageTurnZoneFraction, 0.30);
      expect(policy.hardwareRefreshAvailable, isFalse);
      expect(policy.description, contains('Short page transitions'));
    });

    test('E-Ink is still, page-only, large and high contrast', () {
      const DisplayPolicy policy = DisplayPolicy(profile: DisplayProfile.eink);
      expect(policy.isEink, isTrue);
      expect(policy.reduceMotion, isTrue);
      expect(policy.navigationDuration, Duration.zero);
      expect(policy.chromeAnimationDuration, Duration.zero);
      expect(policy.alignClockToMinute, isTrue);
      expect(policy.forcePagedReader, isTrue);
      expect(policy.forceTapPageTurns, isTrue);
      expect(policy.autoHideReaderChrome, isFalse);
      expect(policy.largeTargets, isTrue);
      expect(policy.highContrast, isTrue);
      expect(policy.selectionOpacity, 0.34);
      expect(policy.readerFontScale, greaterThan(1));
      expect(policy.readerLineHeightDelta, greaterThan(0));
      expect(policy.readerMarginScale, greaterThan(1));
      expect(policy.pageTurnZoneFraction, 0.34);
      expect(policy.hardwareRefreshAvailable, isFalse);
      expect(policy.description, contains('No vendor refresh API'));
    });
  });

  group('nextClockDelay', () {
    test('standard ticks every second', () {
      expect(
        nextClockDelay(
          DateTime(2026, 3, 1, 12, 34, 56, 500),
          DisplayProfile.standard,
        ),
        const Duration(seconds: 1),
      );
    });

    test('E-Ink sleeps until just after the next minute boundary', () {
      expect(
        nextClockDelay(
          DateTime(2026, 3, 1, 12, 34, 56, 500),
          DisplayProfile.eink,
        ),
        const Duration(seconds: 3, milliseconds: 540),
      );
      expect(
        nextClockDelay(
          DateTime(2026, 3, 1, 12, 34, 59, 999),
          DisplayProfile.eink,
        ),
        const Duration(milliseconds: 41),
      );
    });

    test('a fresh boundary waits a full minute instead of spinning', () {
      expect(
        nextClockDelay(DateTime(2026, 3, 1, 12, 34), DisplayProfile.eink),
        const Duration(seconds: 60, milliseconds: 40),
      );
    });
  });

  group('readerSettingsForDisplay', () {
    const ReaderSettings base = ReaderSettings(
      fontSize: 1,
      lineHeight: 1.62,
      margin: 24,
      flow: ReaderFlow.scroll,
      turnMode: PageTurnMode.both,
      showPageNumbers: false,
      keepScreenOn: true,
    );

    test('standard returns the stored object unchanged', () {
      expect(
        identical(readerSettingsForDisplay(base, DisplayPolicy.standard), base),
        isTrue,
      );
    });

    test('E-Ink adjusts a render-time copy and preserves user choices', () {
      const DisplayPolicy eink = DisplayPolicy(profile: DisplayProfile.eink);
      final ReaderSettings adjusted = readerSettingsForDisplay(base, eink);
      expect(adjusted.fontSize, closeTo(1.06, 0.0001));
      expect(adjusted.lineHeight, closeTo(1.68, 0.0001));
      expect(adjusted.margin, closeTo(26.88, 0.0001));
      expect(adjusted.flow, ReaderFlow.paged);
      expect(adjusted.turnMode, PageTurnMode.tap);
      expect(adjusted.showPageNumbers, isFalse);
      expect(adjusted.keepScreenOn, isTrue);
      // The stored values are untouched, so switching back restores them.
      expect(base.fontSize, 1);
      expect(base.lineHeight, 1.62);
      expect(base.margin, 24);
      expect(base.flow, ReaderFlow.scroll);
      expect(base.turnMode, PageTurnMode.both);
    });

    test('E-Ink adjustments stay inside the reader control ranges', () {
      const DisplayPolicy eink = DisplayPolicy(profile: DisplayProfile.eink);
      const ReaderSettings huge = ReaderSettings(
        fontSize: 1.75,
        lineHeight: 2.25,
        margin: 76,
      );
      final ReaderSettings adjusted = readerSettingsForDisplay(huge, eink);
      expect(adjusted.fontSize, 1.75);
      expect(adjusted.lineHeight, 2.25);
      expect(adjusted.margin, 76);
    });
  });

  group('settings persistence', () {
    late SharedPreferences preferences;
    late SettingsRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      preferences = await SharedPreferences.getInstance();
      repository = SettingsRepository(preferences);
    });

    test('saves and reloads the display profile in the v2 envelope', () async {
      await repository.save(
        const AppSettings.defaults().copyWith(
          display: const DisplaySettings(profile: DisplayProfile.eink),
        ),
      );
      final Map<String, Object?> document = jsonDecode(
        preferences.getString(SettingsRepository.settingsKey)!,
      ) as Map<String, Object?>;
      expect(document['version'], 2);
      expect(document['display'], <String, Object?>{'profile': 'eink'});
      expect(repository.load().display.profile, DisplayProfile.eink);
      expect(
        SettingsRepository(preferences).load().display.profile,
        DisplayProfile.eink,
      );
    });

    test('reads a legacy document with no version and no display section', () {
      final Map<String, Object?> legacy = const AppSettings.defaults().toJson();
      legacy.remove('display');
      preferences.setString(SettingsRepository.settingsKey, jsonEncode(legacy));
      expect(repository.load().display.profile, DisplayProfile.standard);
    });

    test(
      'rejects a future settings version without overwriting defaults',
      () async {
        preferences.setString(
          SettingsRepository.settingsKey,
          jsonEncode(<String, Object?>{
            'version': SettingsRepository.documentVersion + 1,
            'settings': const AppSettings.defaults().toJson(),
          }),
        );
        expect(repository.load().display.profile, DisplayProfile.standard);
        await expectLater(
          repository.importJson(
            jsonEncode(<String, Object?>{
              'version': SettingsRepository.documentVersion + 1,
              'settings': const AppSettings.defaults().toJson(),
            }),
          ),
          throwsA(isA<Exception>()),
        );
      },
    );
  });
}
