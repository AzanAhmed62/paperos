import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/storage/app_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late AppStorage storage;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('paperos_storage_');
    storage = AppStorage(rootOverride: () async => temp);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test('removes only stale .part files directly inside the library', () async {
    final Directory library = await storage.library();
    final File stale = File(p.join(library.path, 'stale.epub.part'));
    final File fresh = File(p.join(library.path, 'fresh.epub.part'));
    final File complete = File(p.join(library.path, 'complete.epub'));
    final Directory nested = Directory(p.join(library.path, 'nested'));
    await nested.create();
    final File nestedPart = File(p.join(nested.path, 'nested.epub.part'));
    for (final File file in <File>[stale, fresh, complete, nestedPart]) {
      await file.writeAsBytes(<int>[1, 2, 3], flush: true);
    }
    final DateTime old = DateTime.now().subtract(const Duration(days: 2));
    await stale.setLastModified(old);
    await nestedPart.setLastModified(old);

    final int removed = await storage.purgeAbandonedImports();

    expect(removed, 1);
    expect(stale.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
    expect(complete.existsSync(), isTrue);
    expect(nestedPart.existsSync(), isTrue);
  });

  test('startup cleanup also removes a stale import partial', () async {
    final Directory library = await storage.library();
    final File stale = File(p.join(library.path, 'abandoned.pdf.part'));
    await stale.writeAsBytes(<int>[1], flush: true);
    await stale.setLastModified(
      DateTime.now().subtract(const Duration(days: 2)),
    );

    await storage.cleanupDisposableStorage();

    expect(stale.existsSync(), isFalse);
  });
}
