import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../config/app_config.dart';
import '../../../core/errors/paper_exception.dart';
import '../../../core/platform/document_import_service.dart';
import '../../files/domain/browsed_entry.dart';
import '../../library/data/library_service.dart';
import '../../library/domain/document.dart';
import '../../library/domain/library_models.dart';

/// A library list request: which slice, how to order it, and search text.
class LibraryQuery {
  const LibraryQuery({
    this.scope = LibraryScope.all,
    this.search = '',
    this.sort = LibrarySort.recentlyOpened,
  });

  final LibraryScope scope;
  final String search;
  final LibrarySort sort;

  LibraryQuery copyWith({
    LibraryScope? scope,
    String? search,
    LibrarySort? sort,
  }) => LibraryQuery(
    scope: scope ?? this.scope,
    search: search ?? this.search,
    sort: sort ?? this.sort,
  );
}

class LibraryQueryController extends Notifier<LibraryQuery> {
  @override
  LibraryQuery build() => const LibraryQuery();

  void setScope(LibraryScope scope) => state = state.copyWith(scope: scope);

  void setSearch(String search) => state = state.copyWith(search: search);

  void setSort(LibrarySort sort) => state = state.copyWith(sort: sort);
}

final libraryQueryProvider =
    NotifierProvider<LibraryQueryController, LibraryQuery>(
      LibraryQueryController.new,
    );

/// Emits whenever the document table changes, so that list providers re-query
/// without anyone having to remember to invalidate them.
///
/// Each event carries a distinct number: Riverpod ignores repeated, equal
/// `AsyncData` values, so emitting `void` would refresh only the first change.
final libraryRevisionProvider = StreamProvider<int>((Ref ref) {
  int revision = 0;
  return ref.watch(documentRepositoryProvider).changes.map((_) => ++revision);
});

final bookmarkRevisionProvider = StreamProvider<int>((Ref ref) {
  int revision = 0;
  return ref.watch(bookmarkRepositoryProvider).changes.map((_) => ++revision);
});

/// The documents for the current [libraryQueryProvider], already formatted.
final libraryEntriesProvider = FutureProvider<List<LibraryEntry>>((
  Ref ref,
) async {
  ref.watch(libraryRevisionProvider);
  ref.watch(libraryQueryProvider);
  final LibraryQuery query = ref.read(libraryQueryProvider);
  final DateTime now = DateTime.now();
  final List<Document> documents = await ref
      .watch(documentRepositoryProvider)
      .list(scope: query.scope, sort: query.sort, query: query.search);
  return documents
      .map((Document document) => LibraryService.present(document, now))
      .toList(growable: false);
});

/// The document Paper Home offers to continue reading. Null means "nothing to
/// continue", which the home screen states in words.
final continueReadingProvider = FutureProvider<Document?>((Ref ref) async {
  ref.watch(libraryRevisionProvider);
  return ref.watch(documentRepositoryProvider).mostRecentUnfinished();
});

final recentDocumentsProvider = FutureProvider<List<Document>>((Ref ref) async {
  ref.watch(libraryRevisionProvider);
  return ref
      .watch(documentRepositoryProvider)
      .list(scope: LibraryScope.recent, limit: PaperConfig.homeRecentLimit);
});

final bookmarkCountsProvider = FutureProvider<Map<String, int>>((
  Ref ref,
) async {
  ref.watch(bookmarkRevisionProvider);
  return ref.watch(bookmarkRepositoryProvider).countsByDocument();
});

final documentByIdProvider = FutureProvider.family<Document?, String>((
  Ref ref,
  String id,
) async {
  ref.watch(libraryRevisionProvider);
  return ref.watch(documentRepositoryProvider).findById(id);
});

/// Result of the most recent import attempt, surfaced as a banner on Library.
class ImportOutcome {
  const ImportOutcome({
    required this.title,
    required this.message,
    this.failed = false,
  });

  final String title;
  final String message;
  final bool failed;
}

class ImportController extends Notifier<ImportOutcome?> {
  @override
  ImportOutcome? build() => null;

  /// Opens the system picker and imports whatever comes back.
  ///
  /// A cancel is not an error: [ImportOutcome] is left untouched so no banner
  /// appears.
  Future<Document?> importFromPicker() async {
    final DocumentImportService picker = ref.read(
      documentImportServiceProvider,
    );
    final PickedFile? picked;
    try {
      picked = await picker.pickDocument();
    } on PaperException catch (error) {
      state = ImportOutcome(
        title: 'Import failed',
        message: error.message,
        failed: true,
      );
      return null;
    }
    if (picked == null) return null;
    return importPicked(picked);
  }

  Future<Document?> importPicked(PickedFile picked) async {
    try {
      final Document document = await ref
          .read(libraryServiceProvider)
          .importFile(picked);
      state = ImportOutcome(title: 'Added to library', message: document.title);
      return document;
    } on PaperException catch (error) {
      state = ImportOutcome(
        title: 'Import failed',
        message: error.message,
        failed: true,
      );
      return null;
    }
  }

  /// Imports a file the user tapped in the Files browser.
  ///
  /// The bytes are copied out of the SAF tree into cache first, then flow
  /// through the ordinary import path, so a browsed document and a picked one
  /// end up identical — including the source uri used to avoid duplicates.
  Future<Document?> importBrowsedEntry(BrowsedEntry entry) async {
    final String path;
    try {
      path = await ref.read(fileBrowserServiceProvider).materialise(entry);
    } on PaperException catch (error) {
      state = ImportOutcome(
        title: 'Could not open file',
        message: error.message,
        failed: true,
      );
      return null;
    }

    int byteSize = entry.byteSize ?? 0;
    if (byteSize <= 0) {
      try {
        byteSize = await File(path).length();
      } on FileSystemException {
        byteSize = 0;
      }
    }

    return importPicked(
      PickedFile(
        path: path,
        name: entry.name,
        byteSize: byteSize,
        sourceUri: entry.uri,
      ),
    );
  }

  void dismiss() => state = null;
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportOutcome?>(ImportController.new);

/// Mutations on library documents. Grouped so screens never touch a
/// repository directly.
class LibraryActions {
  const LibraryActions(this._ref);

  final Ref _ref;

  Future<void> toggleFavorite(Document document) => _ref
      .read(documentRepositoryProvider)
      .setFavorite(document.id, !document.isFavorite);

  Future<void> remove(Document document) =>
      _ref.read(libraryServiceProvider).remove(document);

  Future<void> rename(Document document, String title) {
    final String trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == document.title) {
      return Future<void>.value();
    }
    return _ref
        .read(documentRepositoryProvider)
        .update(document.copyWith(title: trimmed));
  }
}

final libraryActionsProvider = Provider<LibraryActions>(LibraryActions.new);
