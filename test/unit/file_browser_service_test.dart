import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/errors/paper_exception.dart';
import 'package:paperos/core/platform/file_browser_service.dart';
import 'package:paperos/features/files/domain/browsed_entry.dart';
import 'package:paperos/features/library/domain/document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('dev.paperos/files');
  const PlatformFileBrowserService service = PlatformFileBrowserService(
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

  tearDown(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('is unsupported off Android and returns empty results', () async {
    const PlatformFileBrowserService desktop = PlatformFileBrowserService(
      android: false,
    );
    expect(desktop.isSupported, isFalse);
    expect(await desktop.listChildren(treeUri: 'content://tree/x'), isEmpty);
    expect(await desktop.takeExternalDocument(), isNull);
    expect(await desktop.pickLocation(), isNull);
  });

  test('listChildren maps platform entries to domain objects', () async {
    mock((MethodCall call) async {
      expect(call.method, 'listChildren');
      expect(call.arguments, <String, Object?>{
        'treeUri': 'content://tree/books',
      });
      return <Object?>[
        <Object?, Object?>{
          'uri': 'content://doc/folder1',
          'name': 'Novels',
          'isDirectory': true,
          'mimeType': 'vnd.android.document/directory',
        },
        <Object?, Object?>{
          'uri': 'content://doc/paper',
          'name': 'paper.pdf',
          'isDirectory': false,
          'mimeType': 'application/pdf',
          'byteSize': 4096,
          'lastModified': 1700000000000,
        },
      ];
    });

    final List<BrowsedEntry> entries = await service.listChildren(
      treeUri: 'content://tree/books',
    );

    expect(entries, hasLength(2));
    expect(entries.first.isDirectory, isTrue);
    expect(entries.first.name, 'Novels');
    expect(entries.last.isReadable, isTrue);
    expect(entries.last.format, DocumentFormat.pdf);
    expect(entries.last.byteSize, 4096);
    expect(entries.last.lastModified, isNotNull);
  });

  test('listChildren forwards a subdirectory uri when given one', () async {
    mock((MethodCall call) async {
      expect(call.arguments, <String, Object?>{
        'treeUri': 'content://tree/books',
        'directoryUri': 'content://doc/folder1',
      });
      return <Object?>[];
    });

    await service.listChildren(
      treeUri: 'content://tree/books',
      directoryUri: 'content://doc/folder1',
    );
  });

  test('listChildren turns access_denied into a permission failure', () async {
    mock((MethodCall call) async {
      throw PlatformException(code: 'access_denied', message: 'no grant');
    });

    await expectLater(
      service.listChildren(treeUri: 'content://tree/books'),
      throwsA(
        isA<PaperException>().having(
          (PaperException e) => e.kind,
          'kind',
          PaperErrorKind.permission,
        ),
      ),
    );
  });

  test('materialise returns the cache path', () async {
    mock((MethodCall call) async {
      expect(call.method, 'materialise');
      return '/data/cache/browser/paper.pdf';
    });

    const BrowsedEntry entry = BrowsedEntry(
      uri: 'content://doc/paper',
      name: 'paper.pdf',
      isDirectory: false,
    );
    expect(await service.materialise(entry), '/data/cache/browser/paper.pdf');
  });

  test('materialise treats an unknown method as a missing file', () async {
    mock((MethodCall call) async => null);
    const BrowsedEntry entry = BrowsedEntry(
      uri: 'content://doc/paper',
      name: 'paper.pdf',
      isDirectory: false,
    );

    await expectLater(
      service.materialise(entry),
      throwsA(
        isA<PaperException>().having(
          (PaperException e) => e.kind,
          'kind',
          PaperErrorKind.missingFile,
        ),
      ),
    );
  });

  test('pickLocation returns the granted tree', () async {
    mock(
      (MethodCall call) async => <Object?, Object?>{
        'uri': 'content://tree/books',
        'label': 'Books',
      },
    );

    final BrowsedLocation? picked = await service.pickLocation();
    expect(picked, isNotNull);
    expect(picked!.uri, 'content://tree/books');
    expect(picked.label, 'Books');
  });

  test('pickLocation returns null when the picker is cancelled', () async {
    mock((MethodCall call) async => null);
    expect(await service.pickLocation(), isNull);
  });

  test('takeExternalDocument parses a VIEW intent', () async {
    mock(
      (MethodCall call) async => <Object?, Object?>{
        'uri': 'content://doc/incoming',
        'name': 'incoming.pdf',
        'mimeType': 'application/pdf',
      },
    );

    final ExternalDocument? document = await service.takeExternalDocument();
    expect(document, isNotNull);
    expect(document!.uri, 'content://doc/incoming');
    expect(document.name, 'incoming.pdf');
  });
}
