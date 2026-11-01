import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../../config/app_config.dart';
import '../../../core/errors/paper_exception.dart';
import '../../annotations/data/annotation_repository.dart';
import '../../annotations/domain/annotation.dart';
import '../../library/data/bookmark_repository.dart';
import '../../library/data/document_repository.dart';
import '../../library/domain/document.dart';

enum AnnotationExportFormat {
  markdown('md', 'Markdown'),
  json('json', 'JSON');

  const AnnotationExportFormat(this.extension, this.label);

  final String extension;
  final String label;
}

/// A deterministic, self-contained representation of one book's annotations.
///
/// The builder is pure so the exact export text can be tested without a file
/// picker. Both formats disclose orphaned annotations instead of quietly
/// dropping rows the current reader cannot anchor.
class AnnotationExport {
  const AnnotationExport({
    required this.markdown,
    required this.json,
    required this.fileStem,
  });

  final String markdown;
  final String json;
  final String fileStem;
}

abstract final class AnnotationExportBuilder {
  static AnnotationExport build({
    required Document document,
    required List<Annotation> annotations,
    required List<Bookmark> bookmarks,
    DateTime? exportedAt,
  }) {
    final DateTime now = (exportedAt ?? DateTime.now()).toLocal();
    final List<Annotation> ordered = List<Annotation>.of(annotations)
      ..sort((Annotation a, Annotation b) {
        final int chapter = (a.chapterIndex ?? 1 << 30).compareTo(
          b.chapterIndex ?? 1 << 30,
        );
        if (chapter != 0) return chapter;
        return a.createdAt.compareTo(b.createdAt);
      });
    final List<Bookmark> orderedBookmarks = List<Bookmark>.of(bookmarks)
      ..sort((Bookmark a, Bookmark b) => a.createdAt.compareTo(b.createdAt));
    final int orphaned = ordered.where((Annotation a) => a.orphaned).length;
    final String exported = _dateTime(now);
    final String safeTitle = _clean(document.title);
    final String author = _clean(document.author ?? '');
    final String stem = '${_filePart(document.title)} annotations';

    final StringBuffer md = StringBuffer()
      ..writeln('# $safeTitle')
      ..writeln();
    if (author.isNotEmpty) {
      md
        ..writeln('*by $author*')
        ..writeln();
    }
    md
      ..writeln('Exported $exported from ${PaperConfig.appName} '
          '${PaperConfig.versionLabel}.')
      ..writeln()
      ..writeln(
        '${ordered.length} annotation${ordered.length == 1 ? '' : 's'}, '
        '${orderedBookmarks.length} bookmark'
        '${orderedBookmarks.length == 1 ? '' : 's'}.',
      )
      ..writeln();
    if (orphaned > 0) {
      md
        ..writeln(
          '> **Orphaned annotations: $orphaned of ${ordered.length}.** '
          'These excerpts are preserved, but their stored position no longer '
          'matches the book in this version of PaperOS. They are marked '
          'individually below.',
        )
        ..writeln();
    }

    if (orderedBookmarks.isNotEmpty) {
      md
        ..writeln('## Bookmarks')
        ..writeln();
      for (final Bookmark bookmark in orderedBookmarks) {
        final String label = _clean(bookmark.displayLabel);
        md.writeln('### $label');
        md.writeln();
        md.writeln('- Location: `${_bookmarkLocation(bookmark)}`');
        if (bookmark.excerpt?.trim().isNotEmpty == true) {
          md
            ..writeln()
            ..writeln(_quote(bookmark.excerpt!));
        }
        md
          ..writeln()
          ..writeln('- Created: ${_dateTime(bookmark.createdAt.toLocal())}')
          ..writeln();
      }
    }

    if (ordered.isNotEmpty) {
      md
        ..writeln('## Annotations')
        ..writeln();
      int? lastChapter;
      String? lastTitle;
      for (final Annotation annotation in ordered) {
        final int? chapter = annotation.chapterIndex;
        final String chapterTitle = _clean(annotation.chapterTitle ?? '');
        if (chapter != lastChapter || chapterTitle != lastTitle) {
          lastChapter = chapter;
          lastTitle = chapterTitle;
          final String heading = chapterTitle.isNotEmpty
              ? chapterTitle
              : (chapter == null ? 'Unplaced' : 'Chapter ${chapter + 1}');
          md
            ..writeln('### $heading')
            ..writeln();
        }
        md
          ..writeln('#### ${annotation.kind.label}')
          ..writeln()
          ..writeln(_quote(annotation.excerpt));
        if (annotation.hasNote) {
          md
            ..writeln()
            ..writeln('**Note:** ${_clean(annotation.note!)}');
        }
        if (annotation.orphaned) {
          md
            ..writeln()
            ..writeln(
              '**Orphaned:** this annotation could not be anchored to the '
              'current text. The excerpt and note above are unchanged.',
            );
        }
        md
          ..writeln()
          ..writeln(
            '- Location: `${annotation.startLocator}` → '
            '`${annotation.endLocator}`',
          )
          ..writeln(
            '- Created: ${_dateTime(annotation.createdAt.toLocal())}',
          );
        if (annotation.updatedAt != annotation.createdAt) {
          md.writeln(
            '- Updated: ${_dateTime(annotation.updatedAt.toLocal())}',
          );
        }
        md.writeln();
      }
    }

    final Map<String, Object?> json = <String, Object?>{
      'format': 'paperos.annotations',
      'version': 1,
      'exportedAt': now.toUtc().toIso8601String(),
      'appVersion': PaperConfig.appVersion,
      'appBuild': PaperConfig.appBuildNumber,
      'book': <String, Object?>{
        'id': document.id,
        'title': document.title,
        'author': document.author,
        'format': document.format.id,
        'pageCount': document.pageCount,
        'progress': document.progressFraction,
        'lastLocator': document.progress.position?.locator,
      },
      'counts': <String, Object?>{
        'annotations': ordered.length,
        'bookmarks': orderedBookmarks.length,
        'orphanedAnnotations': orphaned,
      },
      'orphanedDisclosure': orphaned == 0
          ? null
          : '$orphaned annotation${orphaned == 1 ? '' : 's'} could not be '
                'anchored to the current book. Their excerpts, notes and '
                'original locators are preserved and marked orphaned.',
      'bookmarks': <Object?>[
        for (final Bookmark bookmark in orderedBookmarks)
          <String, Object?>{
            'id': bookmark.id,
            'label': bookmark.displayLabel,
            'chapterTitle': bookmark.chapterTitle,
            'page': bookmark.page >= 0 ? bookmark.page : null,
            'fraction': bookmark.fraction >= 0 ? bookmark.fraction : null,
            'locator': bookmark.locator,
            'excerpt': bookmark.excerpt,
            'createdAt': bookmark.createdAt.toUtc().toIso8601String(),
          },
      ],
      'annotations': <Object?>[
        for (final Annotation annotation in ordered)
          <String, Object?>{
            'id': annotation.id,
            'type': annotation.kind.id,
            'typeLabel': annotation.kind.label,
            'chapterIndex': annotation.chapterIndex,
            'chapterTitle': annotation.chapterTitle,
            'excerpt': annotation.excerpt,
            'note': annotation.note,
            'startLocator': annotation.startLocator,
            'endLocator': annotation.endLocator,
            'orphaned': annotation.orphaned,
            'orphanDisclosure': annotation.orphaned
                ? 'This annotation could not be anchored to the current text. '
                      'The excerpt and note are preserved.'
                : null,
            'createdAt': annotation.createdAt.toUtc().toIso8601String(),
            'updatedAt': annotation.updatedAt.toUtc().toIso8601String(),
          },
      ],
    };

    return AnnotationExport(
      markdown: md.toString(),
      json: const JsonEncoder.withIndent('  ').convert(json),
      fileStem: stem,
    );
  }

  static String _quote(String text) {
    final List<String> lines = text.trim().split(RegExp(r'\r?\n'));
    return lines.map((String line) => '> $line').join('\n');
  }

  static String _bookmarkLocation(Bookmark bookmark) {
    final List<String> parts = <String>[];
    if (bookmark.page >= 0) parts.add('page ${bookmark.page}');
    if (bookmark.fraction >= 0) {
      parts.add('${(bookmark.fraction * 100).round()}%');
    }
    if (bookmark.locator != null && bookmark.locator!.isNotEmpty) {
      parts.add(bookmark.locator!);
    }
    return parts.isEmpty ? 'position unavailable' : parts.join(' · ');
  }

  static String _filePart(String title) {
    final String cleaned = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'Untitled' : cleaned;
  }

  static String _clean(String text) => text
      .replaceAll(RegExp(r'\r?\n'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _dateTime(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

/// Loads a book's annotations and bookmarks, builds both formats, and hands
/// the chosen one to the system save picker.
class AnnotationExportService {
  AnnotationExportService({
    required DocumentRepository documents,
    required AnnotationRepository annotations,
    required BookmarkRepository bookmarks,
  }) : _documents = documents,
       _annotations = annotations,
       _bookmarks = bookmarks;

  final DocumentRepository _documents;
  final AnnotationRepository _annotations;
  final BookmarkRepository _bookmarks;

  Future<AnnotationExport?> build(String documentId) async {
    final Document? document = await _documents.findById(documentId);
    if (document == null) {
      throw const PaperException.missingFile(
        'This book is no longer in the library.',
      );
    }
    final List<Annotation> annotations = await _annotations.listFor(documentId);
    final List<Bookmark> bookmarks = await _bookmarks.listFor(documentId);
    return AnnotationExportBuilder.build(
      document: document,
      annotations: annotations,
      bookmarks: bookmarks,
    );
  }

  /// Returns the saved file's display path, or null when the user cancelled.
  Future<String?> export(
    String documentId,
    AnnotationExportFormat format,
  ) async {
    final AnnotationExport? data = await build(documentId);
    if (data == null) return null;
    final String contents = format == AnnotationExportFormat.markdown
        ? data.markdown
        : data.json;
    try {
      return await FilePicker.saveFile(
        dialogTitle: 'Export annotations as ${format.label}',
        fileName: '${data.fileStem}.${format.extension}',
        type: FileType.custom,
        allowedExtensions: <String>[format.extension],
        bytes: Uint8List.fromList(utf8.encode(contents)),
        lockParentWindow: true,
      );
    } on PaperException {
      rethrow;
    } catch (error) {
      throw PaperException.storage(
        'PaperOS could not save the annotation export.',
        cause: error,
      );
    }
  }
}
