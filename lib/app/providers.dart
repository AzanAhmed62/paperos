import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/platform/document_import_service.dart';
import '../core/platform/file_browser_service.dart';
import '../core/platform/keep_awake_service.dart';
import '../core/platform/launcher_service.dart';
import '../core/platform/pdf_service.dart';
import '../core/storage/app_database.dart';
import '../core/storage/app_storage.dart';
import '../features/files/data/location_repository.dart';
import '../features/library/data/bookmark_repository.dart';
import '../features/library/data/document_repository.dart';
import '../features/library/data/library_service.dart';
import '../features/launcher/data/app_catalog.dart';
import '../features/notes/data/note_repository.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/tasks/data/task_repository.dart';

/// Root dependency wiring.
///
/// Everything the app depends on that is not pure Dart is declared here exactly
/// once. Features never construct a repository, a channel, or a directory
/// themselves — they read a provider — which is what makes every screen in the
/// app testable by overriding one value.

/// Overridden in `main()` after `SharedPreferences.getInstance()` so that
/// settings can be read synchronously everywhere below.
final sharedPreferencesProvider = Provider<SharedPreferences>((Ref ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope.',
  );
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (Ref ref) => SettingsRepository(ref.watch(sharedPreferencesProvider)),
);

final appDatabaseProvider = Provider<AppDatabaseOpener>((Ref ref) {
  final AppDatabaseOpener opener = AppDatabaseOpener();
  ref.onDispose(opener.close);
  return opener;
});

final appStorageProvider = Provider<AppStorage>((Ref ref) {
  return AppStorage();
});

final documentRepositoryProvider = Provider<DocumentRepository>((Ref ref) {
  final DocumentRepository repository = DocumentRepository(
    ref.watch(appDatabaseProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final bookmarkRepositoryProvider = Provider<BookmarkRepository>((Ref ref) {
  final BookmarkRepository repository = BookmarkRepository(
    ref.watch(appDatabaseProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final noteRepositoryProvider = Provider<NoteRepository>((Ref ref) {
  final NoteRepository repository = NoteRepository(
    ref.watch(appDatabaseProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final taskRepositoryProvider = Provider<TaskRepository>((Ref ref) {
  final TaskRepository repository = TaskRepository(
    ref.watch(appDatabaseProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final pdfServiceProvider = Provider<PdfService>(
  (Ref ref) => PlatformPdfService(),
);

final keepAwakeServiceProvider = Provider<KeepAwakeService>(
  (Ref ref) => PlatformKeepAwakeService(),
);

final launcherServiceProvider = Provider<LauncherService>(
  (Ref ref) => PlatformLauncherService(),
);

final documentImportServiceProvider = Provider<DocumentImportService>(
  (Ref ref) => const SystemDocumentImportService(),
);

final fileBrowserServiceProvider = Provider<FileBrowserService>(
  (Ref ref) => const PlatformFileBrowserService(),
);

final locationRepositoryProvider = Provider<LocationRepository>((Ref ref) {
  final LocationRepository repository = LocationRepository(
    ref.watch(appDatabaseProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final libraryServiceProvider = Provider<LibraryService>(
  (Ref ref) => LibraryService(
    documents: ref.watch(documentRepositoryProvider),
    bookmarks: ref.watch(bookmarkRepositoryProvider),
    storage: ref.watch(appStorageProvider),
    pdf: ref.watch(pdfServiceProvider),
  ),
);

final appCatalogProvider = Provider<AppCatalogCache>(
  (Ref ref) => AppCatalogCache(ref.watch(launcherServiceProvider)),
);
