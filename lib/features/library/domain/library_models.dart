import 'package:flutter/foundation.dart';

import 'document.dart';

/// A saved slice of the library, for the Library screen.
///
/// Formats and reading states share one list deliberately: the Library is a
/// reading queue, not a file manager, and two parallel filter systems would
/// make the screen harder to scan on paper-like displays.
enum LibraryScope {
  all('All'),
  epub('EPUB'),
  pdf('PDF'),
  text('TXT'),
  recent('Recent'),
  favorites('Favorites'),
  unread('Unread'),
  inProgress('In progress'),
  completed('Completed');

  const LibraryScope(this.label);

  final String label;
}

/// Restrained sort choices. There is no "popular" or "relevance" because
/// PaperOS has no network and no analytics to invent one.
enum LibrarySort {
  recentlyOpened('Recently opened'),
  recentlyAdded('Recently added'),
  title('Title'),
  author('Author');

  const LibrarySort(this.label);

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

  /// "PDF · 340 pages · 1.2 MB", "EPUB · Jane Austen · 0.8 MB" or a status
  /// warning.
  final String secondary;

  /// "Page 42 · 12%" or "Chapter 3 · 38%" — empty when unread.
  final String progressLine;

  final bool showProgress;

  double get progress => document.progressFraction;
}
