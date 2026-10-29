import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/note.dart';

/// Emits whenever the notes table changes.
///
/// A distinct counter per event is required: Riverpod de-duplicates repeated
/// `AsyncData` values, so a `void` stream would stop refreshing after the first
/// change.
final notesRevisionProvider = StreamProvider<int>((Ref ref) {
  int revision = 0;
  return ref.watch(noteRepositoryProvider).changes.map((_) => ++revision);
});

final notesProvider = FutureProvider<List<Note>>((Ref ref) async {
  ref.watch(notesRevisionProvider);
  return ref.watch(noteRepositoryProvider).list();
});

final noteCountProvider = FutureProvider<int>((Ref ref) async {
  ref.watch(notesRevisionProvider);
  return ref.watch(noteRepositoryProvider).count();
});

final noteByIdProvider = FutureProvider.family<Note?, String>((
  Ref ref,
  String id,
) async {
  ref.watch(notesRevisionProvider);
  return ref.watch(noteRepositoryProvider).findById(id);
});

/// Note mutations. Screens call these; they never touch the repository.
class NoteActions {
  const NoteActions(this._ref);

  final Ref _ref;

  Future<Note> create() => _ref.read(noteRepositoryProvider).create();

  Future<void> save(Note note) =>
      _ref.read(noteRepositoryProvider).update(note);

  Future<void> delete(String id) =>
      _ref.read(noteRepositoryProvider).delete(id);
}

final noteActionsProvider = Provider<NoteActions>(NoteActions.new);
