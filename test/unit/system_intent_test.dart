import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/app/router.dart';
import 'package:paperos/app/system_intent_controller.dart';
import 'package:paperos/core/platform/system_intent_service.dart';
import 'package:paperos/features/files/application/files_providers.dart';
import 'package:paperos/features/files/domain/browsed_entry.dart';

/// A system-intent seam driven by the test rather than by Android.
class _FakeSystemIntents implements SystemIntentService {
  _FakeSystemIntents({this.initial});

  SystemIntentKind? initial;
  SystemIntentKind? pending;
  final StreamController<SystemIntentKind> controller =
      StreamController<SystemIntentKind>.broadcast(sync: true);
  bool disposed = false;

  void emit(SystemIntentKind kind) => controller.add(kind);

  @override
  Future<SystemIntentKind?> claimInitialIntent() async {
    final SystemIntentKind? value = initial;
    initial = null;
    return value;
  }

  @override
  Future<SystemIntentKind?> takePending() async {
    final SystemIntentKind? value = pending;
    pending = null;
    return value;
  }

  @override
  Stream<SystemIntentKind> get intents => controller.stream;

  @override
  void dispose() {
    disposed = true;
    controller.close();
  }
}

String pathOf(GoRouter router) =>
    router.routeInformationProvider.value.uri.path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    PlatformSystemIntentService.channelName,
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('the platform service claims a cold-start intent once', () async {
    final List<MethodCall> calls = <MethodCall>[];
    int readyCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          if (call.method != 'ready') return null;
          readyCalls++;
          return readyCalls == 1 ? 'home' : null;
        });

    final PlatformSystemIntentService service = PlatformSystemIntentService(
      channel: channel,
    );
    addTearDown(service.dispose);

    expect(await service.claimInitialIntent(), SystemIntentKind.home);
    expect(await service.claimInitialIntent(), isNull);
    expect(calls.map((MethodCall call) => call.method), <String>[
      'ready',
      'ready',
    ]);
  });

  test('a warm intent is delivered on the stream', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => null);

    final PlatformSystemIntentService service = PlatformSystemIntentService(
      channel: channel,
    );
    addTearDown(service.dispose);

    final Future<SystemIntentKind> next = service.intents.first;
    final ByteData message = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('systemIntent', 'launcher'),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          PlatformSystemIntentService.channelName,
          message,
          (ByteData? reply) {},
        );

    expect(await next, SystemIntentKind.launcher);
  });

  test('an unknown intent kind is ignored', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => null);

    final PlatformSystemIntentService service = PlatformSystemIntentService(
      channel: channel,
    );
    addTearDown(service.dispose);

    final Future<SystemIntentKind> next = service.intents.first.timeout(
      const Duration(milliseconds: 50),
    );
    final ByteData message = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('systemIntent', 'telepathy'),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          PlatformSystemIntentService.channelName,
          message,
          (ByteData? reply) {},
        );

    await expectLater(next, throwsA(isA<TimeoutException>()));
  });

  test(
    'a HOME intent resets the hierarchy and clears the Files stack',
    () async {
      final _FakeSystemIntents intents = _FakeSystemIntents(
        initial: SystemIntentKind.home,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [systemIntentServiceProvider.overrideWithValue(intents)],
      );
      addTearDown(container.dispose);

      final GoRouter router = container.read(appRouterProvider);
      router.go(Routes.library);
      expect(pathOf(router), Routes.library);

      container
          .read(filesBrowseProvider.notifier)
          .openLocation(
            const BrowsedLocation(
              id: 'loc-1',
              label: 'Books',
              uri: 'content://tree/books',
            ),
          );
      expect(container.read(filesBrowseProvider), isNotEmpty);

      container.read(systemIntentControllerProvider);
      await Future<void>.delayed(Duration.zero);

      expect(pathOf(router), Routes.home);
      expect(container.read(filesBrowseProvider), isEmpty);
    },
  );

  test('a warm LAUNCHER intent returns to Home without a cold start', () async {
    final _FakeSystemIntents intents = _FakeSystemIntents();
    final ProviderContainer container = ProviderContainer(
      overrides: [systemIntentServiceProvider.overrideWithValue(intents)],
    );
    addTearDown(container.dispose);

    final GoRouter router = container.read(appRouterProvider);
    container.read(systemIntentControllerProvider);
    await Future<void>.delayed(Duration.zero);

    router.go(Routes.settings);
    expect(pathOf(router), Routes.settings);

    intents.emit(SystemIntentKind.launcher);
    expect(pathOf(router), Routes.home);
  });

  test('a pending intent is drained on resume', () async {
    final _FakeSystemIntents intents = _FakeSystemIntents();
    final ProviderContainer container = ProviderContainer(
      overrides: [systemIntentServiceProvider.overrideWithValue(intents)],
    );
    addTearDown(container.dispose);

    final GoRouter router = container.read(appRouterProvider);
    container.read(systemIntentControllerProvider);
    await Future<void>.delayed(Duration.zero);

    router.go(Routes.notes);
    intents.pending = SystemIntentKind.home;
    await container
        .read(systemIntentControllerProvider.notifier)
        .drainPending();

    expect(pathOf(router), Routes.home);
  });
}
