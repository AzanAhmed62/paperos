import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/annotation.dart';

/// Emits a distinct number whenever annotations change, so screens re-query
/// without manual invalidation.
final annotationRevisionProvider = StreamProvider<int>((Ref ref) {
  int revision = 0;
  return ref.watch(annotationRepositoryProvider).changes.map((_) => ++revision);
});

final annotationsForDocumentProvider =
    FutureProvider.family<List<Annotation>, String>((Ref ref, String id) async {
      ref.watch(annotationRevisionProvider);
      return ref.watch(annotationRepositoryProvider).listFor(id);
    });

final annotationCountsProvider = FutureProvider<Map<String, int>>((
  Ref ref,
) async {
  ref.watch(annotationRevisionProvider);
  return ref.watch(annotationRepositoryProvider).countsByDocument();
});
