import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/errors/paper_exception.dart';
import 'package:paperos/features/settings/application/settings_controller.dart';
import 'package:paperos/features/settings/data/settings_repository.dart';
import 'package:paperos/features/settings/domain/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FlakySettingsRepository extends SettingsRepository {
  _FlakySettingsRepository(super.preferences);

  bool failNext = true;
  int saves = 0;

  @override
  Future<void> save(AppSettings settings) async {
    saves++;
    if (failNext) {
      failNext = false;
      throw const PaperException.storage('Simulated settings failure.');
    }
    return super.save(settings);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
  });

  ProviderContainer makeContainer({SettingsRepository? repository}) {
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        if (repository != null)
          settingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
  }

  test('updates immediately and persists the title when flushed', () async {
    final ProviderContainer container = makeContainer();
    addTearDown(container.dispose);
    final SettingsController controller = container.read(
      settingsProvider.notifier,
    );

    await controller.setHomeDisplayName('  Quiet Hours  ');

    expect(container.read(settingsProvider).home.displayName, 'Quiet Hours');
    // The in-memory value is immediate; the disk write is coalesced.
    expect(
      SettingsRepository(preferences).load().home.displayName,
      HomeSettings.defaultDisplayName,
    );

    await controller.flushHomeDisplayName();
    expect(
      SettingsRepository(preferences).load().home.displayName,
      'Quiet Hours',
    );
  });

  test('rapid edits persist the latest title, not an older one', () async {
    final ProviderContainer container = makeContainer();
    addTearDown(container.dispose);
    final SettingsController controller = container.read(
      settingsProvider.notifier,
    );

    await controller.setHomeDisplayName('Q');
    await controller.setHomeDisplayName('Quiet');
    await controller.setHomeDisplayName('Quiet Hours');
    await controller.flushHomeDisplayName();

    expect(container.read(settingsProvider).home.displayName, 'Quiet Hours');
    expect(
      SettingsRepository(preferences).load().home.displayName,
      'Quiet Hours',
    );
  });

  test('reset restores and persists the default title', () async {
    final ProviderContainer container = makeContainer();
    addTearDown(container.dispose);
    final SettingsController controller = container.read(
      settingsProvider.notifier,
    );

    await controller.setHomeDisplayName('Night Shelf');
    await controller.flushHomeDisplayName();
    await controller.resetHomeDisplayName();

    expect(
      container.read(settingsProvider).home.displayName,
      HomeSettings.defaultDisplayName,
    );
    expect(
      SettingsRepository(preferences).load().home.displayName,
      HomeSettings.defaultDisplayName,
    );
  });

  test('a later write still persists after an earlier write failed', () async {
    final _FlakySettingsRepository repository = _FlakySettingsRepository(
      preferences,
    );
    final ProviderContainer container = makeContainer(repository: repository);
    addTearDown(container.dispose);
    final SettingsController controller = container.read(
      settingsProvider.notifier,
    );

    await expectLater(
      controller.setShowClock(false),
      throwsA(isA<PaperException>()),
    );
    await controller.setShowClock(true);

    expect(container.read(settingsProvider).home.showClock, isTrue);
    expect(SettingsRepository(preferences).load().home.showClock, isTrue);
    expect(repository.saves, 2);
  });
}
