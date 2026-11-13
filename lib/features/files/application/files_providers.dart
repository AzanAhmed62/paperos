import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/paper_exception.dart';
import '../domain/browsed_entry.dart';

/// One level inside a granted location.
@immutable
class FilesBrowseStep {
  const FilesBrowseStep({
    required this.location,
    required this.directoryUri,
    required this.label,
  });

  final BrowsedLocation location;

  /// Null means the location's root.
  final String? directoryUri;
  final String label;
}

/// The folder path currently open in Files.
///
/// It lives in Riverpod rather than in the screen's State because Android Back
/// is handled by the shell. The shell must be able to ask "is Files inside a
/// folder?" and step out without reaching into a descendant's private state.
class FilesBrowseController extends Notifier<List<FilesBrowseStep>> {
  @override
  List<FilesBrowseStep> build() => const <FilesBrowseStep>[];

  void openLocation(BrowsedLocation location) {
    state = <FilesBrowseStep>[
      FilesBrowseStep(
        location: location,
        directoryUri: null,
        label: location.label,
      ),
    ];
  }

  void push(FilesBrowseStep step) {
    state = <FilesBrowseStep>[...state, step];
  }

  /// Steps out one folder. Returns false at the location root.
  bool pop() {
    if (state.isEmpty) return false;
    state = state.sublist(0, state.length - 1);
    return true;
  }

  void reset() {
    if (state.isNotEmpty) state = const <FilesBrowseStep>[];
  }
}

final filesBrowseProvider =
    NotifierProvider<FilesBrowseController, List<FilesBrowseStep>>(
      FilesBrowseController.new,
    );

/// Emits whenever the `locations` table changes.
///
/// The counter keeps every event distinct; a `void` event would be de-duplicated
/// by Riverpod after the first change and the folder list would go stale.
final locationsRevisionProvider = StreamProvider<int>((Ref ref) {
  int revision = 0;
  return ref.watch(locationRepositoryProvider).changes.map((_) => ++revision);
});

/// The folders the user has granted PaperOS access to, in the order they were
/// added.
final locationsProvider = FutureProvider<List<BrowsedLocation>>((
  Ref ref,
) async {
  ref.watch(locationsRevisionProvider);
  return ref.watch(locationRepositoryProvider).list();
});

/// A request to list one folder (or the root of a location).
@immutable
class BrowseRequest {
  const BrowseRequest({required this.location, this.directoryUri});

  final BrowsedLocation location;

  /// Null lists the location's root; otherwise the uri of the subfolder.
  final String? directoryUri;

  @override
  bool operator ==(Object other) =>
      other is BrowseRequest &&
      other.location.uri == location.uri &&
      other.directoryUri == directoryUri;

  @override
  int get hashCode => Object.hash(location.uri, directoryUri);
}

/// The children of one folder.
final folderChildrenProvider =
    FutureProvider.family<List<BrowsedEntry>, BrowseRequest>((
      Ref ref,
      BrowseRequest request,
    ) {
      return ref
          .watch(fileBrowserServiceProvider)
          .listChildren(
            treeUri: request.location.uri,
            directoryUri: request.directoryUri,
          );
    });

/// Mutations on the list of locations. Screens never touch the repository.
class LocationActions {
  const LocationActions(this._ref);

  final Ref _ref;

  /// Shows the folder picker and remembers what the user chose.
  ///
  /// Returns null when the user cancels or the platform has no folder picker;
  /// throws [PaperException] only for a real failure.
  Future<BrowsedLocation?> addLocation() async {
    final BrowsedLocation? picked = await _ref
        .read(fileBrowserServiceProvider)
        .pickLocation();
    if (picked == null) return null;
    return _ref
        .read(locationRepositoryProvider)
        .add(label: picked.label, uri: picked.uri);
  }

  /// Forgets a location and releases the platform grant behind it.
  Future<void> removeLocation(BrowsedLocation location) async {
    await _ref.read(locationRepositoryProvider).remove(location.id);
    await _ref.read(fileBrowserServiceProvider).releaseLocation(location);
  }
}

final locationActionsProvider = Provider<LocationActions>(LocationActions.new);
