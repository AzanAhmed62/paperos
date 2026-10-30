import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../config/app_config.dart';
import '../errors/paper_exception.dart';

/// PaperOS' own directory layout inside app-private storage.
///
/// ```
/// <app documents>/
///   library/     one file per library entry (private copy of the import)
///   notes/       note exports
///   trash/       deleted documents, kept for 7 days
/// ```
///
/// Everything is inside `getApplicationDocumentsDirectory()`, which on Android
/// maps to the app's internal `files/` directory: no runtime permission, backed
/// up only if the user opts in, and not visible to other apps.
class AppStorage {
  AppStorage({Future<Directory> Function()? rootOverride})
    : _rootOverride = rootOverride;

  final Future<Directory> Function()? _rootOverride;

  Directory? _root;
  final Map<String, Directory> _created = <String, Directory>{};

  Future<Directory> root() async {
    final Directory? cached = _root;
    if (cached != null) return cached;
    try {
      final Directory directory = _rootOverride != null
          ? await _rootOverride()
          : await getApplicationDocumentsDirectory();
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
      _root = directory;
      return directory;
    } catch (error) {
      throw PaperException.storage(
        'PaperOS could not access its own storage on this device.',
        cause: error,
      );
    }
  }

  /// A named sub-directory of app storage, created on demand.
  Future<Directory> ensure(String name) async {
    final Directory? cached = _created[name];
    if (cached != null) return cached;
    final Directory directory = Directory(p.join((await root()).path, name));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    _created[name] = directory;
    return directory;
  }

  Future<Directory> library() => ensure(PaperConfig.libraryDirectoryName);

  Future<Directory> notes() => ensure('notes');

  /// Small extracted EPUB covers. Kept outside the library copy so deleting a
  /// document cannot leave the database pointing at half a book.
  Future<Directory> covers() => ensure('covers');

  Future<Directory> trash() => ensure('trash');

  /// Human readable summary of how much space PaperOS is using.
  Future<StorageUsage> usage() async {
    final Directory libraryDir = await library();
    int bytes = 0;
    int files = 0;
    await for (final FileSystemEntity entity in libraryDir.list()) {
      if (entity is File) {
        files++;
        try {
          bytes += await entity.length();
        } on FileSystemException {
          // A file deleted mid-scan is not an error worth surfacing.
        }
      }
    }
    return StorageUsage(bytes: bytes, files: files, path: libraryDir.path);
  }

  /// Deletes a library copy, quarantining it in `trash/` first. Returns true
  /// when the file was moved, false when it was already gone.
  Future<bool> trashFile(String path) async {
    final File file = File(path);
    if (!file.existsSync()) return false;
    final Directory trashDir = await trash();
    final String target = p.join(
      trashDir.path,
      '${DateTime.now().millisecondsSinceEpoch}_${p.basename(path)}',
    );
    try {
      await file.rename(target);
    } on FileSystemException {
      // Rename fails across filesystems and when the name collides; fall back
      // to a copy followed by a delete so the operation still completes.
      await file.copy(target);
      await file.delete();
    }
    return true;
  }

  /// Removes quarantined files older than [maxAge]. Called on startup.
  Future<int> purgeTrash({Duration maxAge = const Duration(days: 7)}) async {
    final Directory trashDir = await trash();
    final DateTime cutoff = DateTime.now().subtract(maxAge);
    int removed = 0;
    await for (final FileSystemEntity entity in trashDir.list()) {
      if (entity is! File) continue;
      try {
        if (await entity.lastModified().then(
          (DateTime t) => t.isBefore(cutoff),
        )) {
          await entity.delete();
          removed++;
        }
      } on FileSystemException {
        // Leave anything we cannot judge or remove.
      }
    }
    return removed;
  }
}

class StorageUsage {
  const StorageUsage({
    required this.bytes,
    required this.files,
    required this.path,
  });

  final int bytes;
  final int files;
  final String path;
}
