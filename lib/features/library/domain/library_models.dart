import 'package:flutter/foundation.dart';

import 'document.dart';

/// A saved slice of the library, for the Library screen.
enum LibraryScope {
  all('All'),
  recent('Recent'),
  favorites('Favorites');

  const LibraryScope(this.label);

  final String label;
}

/// A single row in a library list: a document plus the pre-formatted strings
/// the row needs.
///
/// Formatting happens once, in the provider, so that `build` methods stay free
/// of string work and rows become cheap to compare.
@immutable
class LibraryEntry {
  const LibraryEntry({
    required this.document,
    required this.primary,
    required this.secondary,
    required this.progressLine,
    required this.showProgress,
  });

  final Document document;

  /// Document title.
  final String primary;

  /// "PDF · 340 pages · 1.2 MB" or a status warning.
  final String secondary;

  /// "Page 42 · 12%" — empty when the document was never opened.
  final String progressLine;

  final bool showProgress;

  double get progress => document.progressFraction;
}
