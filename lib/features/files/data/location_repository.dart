import 'dart:async';

import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/errors/paper_exception.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/utils/ids.dart';
import '../domain/browsed_entry.dart';

/// Remembers the folders the user has granted PaperOS access to.
///
/// The stored `path` is the SAF tree uri. It is only ever handed back to the
/// platform; turning it into a filesystem path is neither possible nor desired
/// on Android 11+.
class LocationRepository {
  LocationRepository(this._opener);

  final AppDatabaseOpener _opener;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() async => _changes.close();

  Future<sqflite.Database> get _db => _opener.database;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PaperException {
      rethrow;
    } catch (error) {
      throw PaperException.storage(
        'PaperOS could not read its list of folders.',
        cause: error,
      );
    }
  }

  Future<List<BrowsedLocation>> list() {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).query(
        'locations',
        columns: <String>['id', 'label', 'path'],
        orderBy: 'added_at ASC',
      );
      return rows.map(_fromRow).toList(growable: false);
    });
  }

  /// Adds [uri] if it is not already tracked. Re-adding the same tree returns
  /// the existing row rather than violating the table's unique index.
  Future<BrowsedLocation> add({required String label, required String uri}) {
    return _guard(() async {
      final List<Map<String, Object?>> existing = await (await _db).query(
        'locations',
        where: 'path = ?',
        whereArgs: <Object?>[uri],
        limit: 1,
      );
      if (existing.isNotEmpty) return _fromRow(existing.first);

      final BrowsedLocation location = BrowsedLocation(
        id: newLocalId(),
        uri: uri,
        label: label,
      );
      await (await _db).insert('locations', <String, Object?>{
        'id': location.id,
        'label': location.label,
        'path': location.uri,
        'is_system': 0,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      });
      _notify();
      return location;
    });
  }

  Future<void> remove(String id) {
    return _guard(() async {
      await (await _db).delete(
        'locations',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      _notify();
    });
  }

  static BrowsedLocation _fromRow(Map<String, Object?> row) => BrowsedLocation(
    id: row['id']! as String,
    uri: row['path']! as String,
    label: (row['label'] as String?) ?? 'Folder',
  );
}
