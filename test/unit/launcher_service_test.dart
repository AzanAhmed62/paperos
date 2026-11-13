import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/errors/paper_exception.dart';
import 'package:paperos/core/platform/installed_app.dart';
import 'package:paperos/core/platform/launcher_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    PlatformLauncherService.channelName,
  );
  final PlatformLauncherService service = PlatformLauncherService(
    channel: channel,
    android: true,
  );

  final List<MethodCall> calls = <MethodCall>[];

  void mock(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);

  tearDown(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('is unsupported off Android and fails closed', () async {
    final PlatformLauncherService desktop = PlatformLauncherService(
      channel: channel,
      android: false,
    );

    expect(desktop.support, AppCatalogSupport.unsupported);
    expect(await desktop.isHomeApp(), isFalse);
    expect(await desktop.loadIcon('com.example'), isNull);
    expect(
      desktop.loadApps(),
      throwsA(
        isA<PaperException>().having(
          (PaperException error) => error.kind,
          'kind',
          PaperErrorKind.platform,
        ),
      ),
    );
  });

  test('loadApps maps activities and the restricted flag', () async {
    mock((MethodCall call) async {
      expect(call.method, 'loadApps');
      return <Object?, Object?>{
        'apps': <Object?>[
          <Object?, Object?>{
            'packageName': 'com.example.reader',
            'activityName': 'com.example.reader.Main',
            'label': 'Reader',
            'isSystem': false,
          },
          <Object?, Object?>{
            'packageName': 'com.android.settings',
            'activityName': 'com.android.settings.Settings',
            'label': 'Settings',
            'isSystem': true,
          },
          <Object?, Object?>{'packageName': '', 'label': 'Broken'},
        ],
        'restricted': true,
      };
    });

    final AppCatalogSnapshot snapshot = await service.loadApps();

    expect(snapshot.restricted, isTrue);
    expect(snapshot.apps, hasLength(2));
    expect(snapshot.apps.first.label, 'Reader');
    expect(snapshot.apps.last.isSystem, isTrue);
  });

  test('a missing apps list is an empty snapshot, not a crash', () async {
    mock((MethodCall call) async => <Object?, Object?>{'restricted': false});

    final AppCatalogSnapshot snapshot = await service.loadApps();
    expect(snapshot.apps, isEmpty);
    expect(snapshot.restricted, isFalse);
  });

  test('loadIcon returns the platform bitmap', () async {
    final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
    mock((MethodCall call) async {
      expect(call.method, 'loadIcon');
      expect(call.arguments, <String, Object?>{
        'packageName': 'com.example.reader',
        'sizePx': 96,
      });
      return bytes;
    });

    expect(await service.loadIcon('com.example.reader'), bytes);
  });

  test(
    'launchApp targets the exact component the catalogue declared',
    () async {
      mock((MethodCall call) async {
        expect(call.method, 'launchApp');
        expect(call.arguments, <String, Object?>{
          'packageName': 'com.example.reader',
          'activityName': 'com.example.reader.Main',
        });
        return true;
      });

      await service.launchApp(
        const InstalledApp(
          packageName: 'com.example.reader',
          activityName: 'com.example.reader.Main',
          label: 'Reader',
          isSystem: false,
        ),
      );
    },
  );

  test('requestHomeApp parses each role flow', () async {
    for (final MapEntry<String, HomeRoleFlow> entry in <String, HomeRoleFlow>{
      'role_request': HomeRoleFlow.roleRequest,
      'settings': HomeRoleFlow.settings,
      'already': HomeRoleFlow.already,
      'unavailable': HomeRoleFlow.unavailable,
    }.entries) {
      mock(
        (MethodCall call) async => <Object?, Object?>{
          'isHomeApp': entry.value == HomeRoleFlow.already,
          'flow': entry.key,
        },
      );

      final HomeRoleStatus status = await service.requestHomeApp();
      expect(status.flow, entry.value);
    }
  });

  test('a missing plugin is reported as unavailable, not as a crash', () async {
    final PlatformLauncherService missing = PlatformLauncherService(
      channel: const MethodChannel('dev.paperos/not_installed'),
      android: true,
    );

    expect(await missing.isHomeApp(), isFalse);
    expect((await missing.requestHomeApp()).flow, HomeRoleFlow.unavailable);
    expect(
      missing.loadApps(),
      throwsA(
        isA<PaperException>().having(
          (PaperException error) => error.message,
          'message',
          contains('not available'),
        ),
      ),
    );
  });
}
