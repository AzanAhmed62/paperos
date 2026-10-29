import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/files/data/location_repository.dart';
import 'package:paperos/features/files/domain/browsed_entry.dart';

import 'support.dart';

void main() {
  initFfi();

  late AppDatabaseOpener opener;
  late LocationRepository locations;

  setUp(() {
    opener = openTestDatabase();
    locations = LocationRepository(opener);
  });

  tearDown(() async {
    await locations.dispose();
    await (await opener.database).close();
  });

  test('starts empty', () async {
    expect(await locations.list(), isEmpty);
  });

  test('adds and lists a location in insertion order', () async {
    await locations.add(label: 'Books', uri: 'content://tree/books');
    await locations.add(label: 'Papers', uri: 'content://tree/papers');

    final List<BrowsedLocation> all = await locations.list();
    expect(all.map((BrowsedLocation l) => l.label), <String>[
      'Books',
      'Papers',
    ]);
    expect(all.first.uri, 'content://tree/books');
    expect(all.first.id, isNotEmpty);
  });

  test('re-adding the same uri returns the existing row', () async {
    final BrowsedLocation first = await locations.add(
      label: 'Books',
      uri: 'content://tree/books',
    );
    final BrowsedLocation second = await locations.add(
      label: 'Books again',
      uri: 'content://tree/books',
    );

    expect(second.id, first.id);
    expect(await locations.list(), hasLength(1));
  });

  test('removes a location by id', () async {
    final BrowsedLocation added = await locations.add(
      label: 'Books',
      uri: 'content://tree/books',
    );
    await locations.remove(added.id);
    expect(await locations.list(), isEmpty);
  });

  test('emits a change event after adding', () async {
    final Future<void> change = locations.changes.first;
    await locations.add(label: 'Books', uri: 'content://tree/books');
    await expectLater(change, completes);
  });
}
