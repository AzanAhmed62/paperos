import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/config/app_config.dart';
import 'package:paperos/core/display/display_profile.dart';
import 'package:paperos/core/errors/paper_exception.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/core/storage/app_storage.dart';
import 'package:paperos/features/annotations/data/annotation_repository.dart';
import 'package:paperos/features/annotations/domain/annotation.dart';
import 'package:paperos/features/backup/data/backup_archive.dart';
import 'package:paperos/features/backup/data/backup_service.dart';
import 'package:paperos/features/backup/domain/backup_manifest.dart';
import 'package:paperos/features/files/data/location_repository.dart';
import 'package:paperos/features/library/data/bookmark_repository.dart';
import 'package:paperos/features/library/data/document_repository.dart';
import 'package:paperos/features/library/domain/document.dart';
import 'package:paperos/features/notes/data/note_repository.dart';
import 'package:paperos/features/settings/data/settings_repository.dart';
import 'package:paperos/features/settings/domain/app_settings.dart';
import 'package:paperos/features/tasks/data/task_repository.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

void main() {
  initFfi();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;
  late AppDatabaseOpener opener;
  late AppStorage storage;
  late SettingsRepository settingsRepository;
  late BackupService service;
  late DocumentRepository documents;
  late BookmarkRepository bookmarks;
  late AnnotationRepository annotations;
  late NoteRepository notes;
  late TaskRepository tasks;
  late LocationRepository locations;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('paperos-backup-test-');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    settingsRepository = SettingsRepository(preferences);
    opener = AppDatabaseOpener(
      factory: databaseFactoryFfi,
      path: p.join(temporary.path, 'paperos.db'),
    );
    storage = AppStorage(
      rootOverride: () async => Directory(p.join(temporary.path, 'storage')),
    );
    service = BackupService(
      database: opener,
      storage: storage,
      settings: settingsRepository,
      databaseFactory: databaseFactoryFfi,
    );
    documents = DocumentRepository(opener);
    bookmarks = BookmarkRepository(opener);
    annotations = AnnotationRepository(opener);
    notes = NoteRepository(opener);
    tasks = TaskRepository(opener);
    locations = LocationRepository(opener);
  });

  tearDown(() async {
    await bookmarks.dispose();
    await annotations.dispose();
    await notes.dispose();
    await tasks.dispose();
    await locations.dispose();
    await documents.dispose();
    await opener.close();
    try {
      await temporary.delete(recursive: true);
    } on FileSystemException {
      // Windows may briefly hold the SQLite file; the temp directory is
      // harmless and the next test gets a fresh one.
    }
  });

  Future<Document> seedLibrary({
    String id = 'doc-1',
    String title = 'A Paper Book',
  }) async {
    final Directory library = await storage.library();
    final Directory covers = await storage.covers();
    final File book = File(p.join(library.path, '$id.epub'));
    final File cover = File(p.join(covers.path, '$id.jpg'));
    await book.writeAsBytes(<int>[80, 75, 3, 4, 1, 2, 3, 4], flush: true);
    await cover.writeAsBytes(<int>[255, 216, 255, 9], flush: true);
    final Document document =
        makeDocument(
          id: id,
          title: title,
          format: DocumentFormat.epub,
          localPath: book.path,
        ).copyWith(
          author: 'Ada Lovelace',
          publisher: 'Paper Press',
          language: 'en',
          identifier: 'urn:isbn:1',
          description: 'A test book.',
          coverPath: cover.path,
          fingerprint: 'fingerprint-$id',
          byteSize: 8,
        );
    await documents.insert(document);
    return document;
  }

  Future<void> seedEverything() async {
    final Document document = await seedLibrary();
    await bookmarks.add(
      documentId: document.id,
      position: const ReadingPosition.atPage(
        3,
        fraction: 0.25,
        locator: 'epub:spine=1;char=4',
      ),
      label: 'A bookmark',
      excerpt: 'The bookmark excerpt',
      chapterTitle: 'Chapter One',
    );
    final Annotation anchored = await annotations.add(
      documentId: document.id,
      kind: AnnotationKind.highlight,
      startLocator: 'epub:spine=1;char=10',
      endLocator: 'epub:spine=1;char=20',
      excerpt: 'An anchored excerpt',
      chapterIndex: 0,
      chapterTitle: 'Chapter One',
      note: 'An anchored note',
    );
    final Annotation orphan = await annotations.add(
      documentId: document.id,
      kind: AnnotationKind.note,
      startLocator: 'epub:spine=9;char=1',
      endLocator: 'epub:spine=9;char=3',
      excerpt: 'An orphan excerpt',
      chapterIndex: 8,
      chapterTitle: 'Old Chapter',
    );
    await annotations.markOrphaned(orphan.id);
    expect(anchored.orphaned, isFalse);
    await notes.create(title: 'A note', body: 'A note body');
    await tasks.create(title: 'A task', dueDate: DateTime(2026, 3, 4));
    await locations.add(label: 'Downloaded', uri: 'content://tree/downloads');
  }

  test('round-trips every table, attachment and setting', () async {
    await seedEverything();
    const AppSettings original = AppSettings.defaults();
    final AppSettings custom = original.copyWith(
      display: const DisplaySettings(profile: DisplayProfile.eink),
      askOnExit: false,
    );
    await settingsRepository.save(custom);

    final BackupResult created = await service.createBackup(settings: custom);
    expect(await File(created.path).exists(), isTrue);
    final BackupPreview preview = await service.inspect(
      archivePath: created.path,
      displayName: 'roundtrip.paperosbackup',
    );
    expect(preview.manifest.counts.documents, 1);
    expect(preview.manifest.counts.bookmarks, 1);
    expect(preview.manifest.counts.annotations, 2);
    expect(preview.manifest.counts.notes, 1);
    expect(preview.manifest.counts.tasks, 1);
    expect(preview.manifest.counts.locations, 1);
    expect(preview.manifest.entries.any((e) => e.type.id == 'book'), isTrue);
    expect(preview.manifest.entries.any((e) => e.type.id == 'cover'), isTrue);

    // Change the live library after the backup: restore must replace it.
    await settingsRepository.save(original);
    await notes.create(title: 'Post-backup note', body: 'must disappear');
    await locations.add(label: 'Later', uri: 'content://tree/later');
    await seedLibrary(id: 'doc-2', title: 'Post-backup book');

    final RestoreResult restored = await service.restore(
      preview: preview,
      currentSettings: original,
    );
    expect(await File(restored.safetySnapshotPath).exists(), isTrue);

    final DatabaseSnapshot fresh = await _snapshot(opener);
    expect(fresh.counts['documents'], 1);
    expect(fresh.counts['bookmarks'], 1);
    expect(fresh.counts['annotations'], 2);
    expect(fresh.counts['notes'], 1);
    expect(fresh.counts['tasks'], 1);
    expect(fresh.counts['locations'], 1);

    final Document? restoredBook = await documents.findById('doc-1');
    expect(restoredBook, isNotNull);
    expect(restoredBook!.title, 'A Paper Book');
    expect(restoredBook.author, 'Ada Lovelace');
    expect(restoredBook.coverPath, isNotNull);
    expect(await File(restoredBook.localPath).exists(), isTrue);
    expect(await File(restoredBook.coverPath!).exists(), isTrue);
    expect(restoredBook.byteSize, 8);
    expect(await documents.findById('doc-2'), isNull);

    final List<Bookmark> restoredBookmarks = await bookmarks.listFor('doc-1');
    expect(restoredBookmarks.single.label, 'A bookmark');
    final List<Annotation> restoredAnnotations = await annotations.listFor(
      'doc-1',
    );
    expect(restoredAnnotations.length, 2);
    expect(restoredAnnotations.where((a) => a.orphaned).length, 1);
    expect(
      restoredAnnotations.firstWhere((a) => a.orphaned).excerpt,
      'An orphan excerpt',
    );
    expect((await notes.list()).single.title, 'A note');
    expect((await tasks.forDay(DateTime(2026, 3, 4))).single.title, 'A task');
    expect((await locations.list()).single.uri, 'content://tree/downloads');

    final AppSettings restoredSettings = settingsRepository.load();
    expect(restoredSettings.display.profile, DisplayProfile.eink);
    expect(restoredSettings.askOnExit, isFalse);
  });

  test('restores an empty library over a populated one', () async {
    final BackupResult empty = await service.createBackup(
      settings: const AppSettings.defaults(),
    );
    await seedEverything();
    await settingsRepository.save(
      const AppSettings.defaults().copyWith(askOnExit: false),
    );
    final BackupPreview preview = await service.inspect(
      archivePath: empty.path,
      displayName: 'empty.paperosbackup',
    );

    final RestoreResult result = await service.restore(
      preview: preview,
      currentSettings: const AppSettings.defaults(),
    );
    expect(result.counts.documents, 0);
    final DatabaseSnapshot snapshot = await _snapshot(opener);
    for (final int count in snapshot.counts.values) {
      expect(count, 0);
    }
    expect(settingsRepository.load().askOnExit, isTrue);
  });

  test('cancelling before restore leaves the live library untouched', () async {
    await seedEverything();
    final BackupResult backup = await service.createBackup(
      settings: const AppSettings.defaults(),
    );
    final BackupPreview preview = await service.inspect(
      archivePath: backup.path,
      displayName: 'cancel.paperosbackup',
    );
    final DatabaseSnapshot before = await _snapshot(opener);

    await expectLater(
      service.restore(
        preview: preview,
        currentSettings: const AppSettings.defaults(),
        isCancelled: () => true,
      ),
      throwsA(
        isA<PaperException>().having(
          (PaperException e) => e.kind,
          'kind',
          PaperErrorKind.cancelled,
        ),
      ),
    );
    final DatabaseSnapshot after = await _snapshot(opener);
    expect(after.counts, before.counts);
  });

  test(
    'a damaged payload is refused and does not replace the library',
    () async {
      await seedEverything();
      final BackupResult backup = await service.createBackup(
        settings: const AppSettings.defaults(),
      );
      final byte0 = backup.manifest.entries
          .firstWhere((e) => e.type.id == 'book')
          .path;
      final String damaged = p.join(temporary.path, 'damaged.paperosbackup');
      await _rewriteArchive(backup.path, damaged, (Archive archive) {
        final int index = archive.files.indexWhere(
          (ArchiveFile file) => file.name == byte0,
        );
        final ArchiveFile file = archive.files[index];
        final List<int> bytes = List<int>.of(file.content, growable: true);
        bytes[0] = (bytes[0] + 1) & 0xff;
        archive.modifyAtIndex(index, ArchiveFile.bytes(file.name, bytes));
      });
      final BackupPreview damagedPreview = await service.inspect(
        archivePath: damaged,
        displayName: 'damaged.paperosbackup',
      );
      final DatabaseSnapshot before = await _snapshot(opener);

      await expectLater(
        service.restore(
          preview: damagedPreview,
          currentSettings: const AppSettings.defaults(),
        ),
        throwsA(isA<PaperException>()),
      );
      final DatabaseSnapshot after = await _snapshot(opener);
      expect(after.counts, before.counts);
      expect((await documents.findById('doc-1'))!.title, 'A Paper Book');
    },
  );

  test(
    'inspect refuses a manifest entry whose attachment is missing',
    () async {
      await seedEverything();
      final BackupResult backup = await service.createBackup(
        settings: const AppSettings.defaults(),
      );
      final String bookPath = backup.manifest.entries
          .firstWhere((e) => e.type.id == 'book')
          .path;
      final String missing = p.join(temporary.path, 'missing.paperosbackup');
      await _rewriteArchive(backup.path, missing, (Archive archive) {
        archive.removeAt(
          archive.files.indexWhere((ArchiveFile file) => file.name == bookPath),
        );
      });
      await expectLater(
        service.inspect(
          archivePath: missing,
          displayName: 'missing.paperosbackup',
        ),
        throwsA(
          isA<PaperException>().having(
            (PaperException error) => error.message,
            'message',
            contains('missing'),
          ),
        ),
      );
    },
  );

  test('rejects a future backup manifest before touching live data', () async {
    final Map<String, Object?> json = <String, Object?>{
      'format': PaperConfig.backupFormat,
      'version': PaperConfig.backupFormatVersion + 1,
      'appVersion': '99.0.0',
      'schemaVersion': PaperConfig.databaseVersion,
      'createdAt': DateTime.utc(2026).toIso8601String(),
      'counts': <String, Object?>{
        'documents': 0,
        'bookmarks': 0,
        'annotations': 0,
        'notes': 0,
        'tasks': 0,
        'locations': 0,
      },
      'entries': <Object?>[],
      'libraryBytes': 0,
      'warnings': <Object?>[],
    };
    expect(
      () => BackupManifest.fromJson(json),
      throwsA(
        isA<FormatException>().having(
          (FormatException e) => e.message,
          'message',
          contains('newer version'),
        ),
      ),
    );
  });

  test('malformed manifest list fields are rejected as format errors', () {
    final Map<String, Object?> json = <String, Object?>{
      'format': PaperConfig.backupFormat,
      'version': PaperConfig.backupFormatVersion,
      'appVersion': '1.2.0',
      'schemaVersion': PaperConfig.databaseVersion,
      'createdAt': DateTime.utc(2026).toIso8601String(),
      'counts': <String, Object?>{
        'documents': 0,
        'bookmarks': 0,
        'annotations': 0,
        'notes': 0,
        'tasks': 0,
        'locations': 0,
      },
      'entries': 'not-a-list',
      'libraryBytes': 0,
      'warnings': <Object?>[],
    };
    expect(
      () => BackupManifest.fromJson(json),
      throwsA(isA<FormatException>()),
    );

    json['entries'] = <Object?>[];
    json['warnings'] = 'not-a-list';
    expect(
      () => BackupManifest.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'inspect rejects path traversal without decompressing payloads',
    () async {
      final String path = p.join(temporary.path, 'traversal.paperosbackup');
      final Archive archive = Archive();
      archive.addFile(ArchiveFile('../outside.txt', 3, <int>[1, 2, 3]));
      await File(path).writeAsBytes(ZipEncoder().encode(archive), flush: true);
      expect(
        () => BackupArchive.inspect(path),
        throwsA(isA<FormatException>()),
      );
    },
  );
}

class DatabaseSnapshot {
  const DatabaseSnapshot(this.counts);
  final Map<String, int> counts;
}

Future<DatabaseSnapshot> _snapshot(AppDatabaseOpener opener) async {
  final sqflite.Database database = await opener.database;
  final Map<String, int> counts = <String, int>{};
  for (final String table in const <String>[
    'documents',
    'bookmarks',
    'annotations',
    'notes',
    'tasks',
    'locations',
  ]) {
    final List<Map<String, Object?>> rows = await database.rawQuery(
      'SELECT COUNT(*) AS n FROM "$table"',
    );
    counts[table] = (rows.first['n'] as int?) ?? 0;
  }
  return DatabaseSnapshot(counts);
}

Future<void> _rewriteArchive(
  String source,
  String destination,
  void Function(Archive archive) mutate,
) async {
  final Archive archive = ZipDecoder().decodeBytes(
    await File(source).readAsBytes(),
  );
  mutate(archive);
  await File(destination)
      .writeAsBytes(ZipEncoder().encode(archive), flush: true);
}
