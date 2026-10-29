import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../config/app_config.dart';
import '../../../core/errors/paper_exception.dart';
import '../../../core/platform/document_import_service.dart';
import '../../../core/platform/pdf_service.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/ids.dart';
import '../domain/document.dart';
import '../domain/library_models.dart';
import 'bookmark_repository.dart';
import 'document_repository.dart';

/// Everything that happens to a document between "the user picked a file" and
/// "the library can open it".
///
/// Copying happens here, deliberately, rather than reading from the original
/// location: a SAF grant can be revoked at any time, and a library that loses
/// books silently is worse than one that uses disk.
class LibraryService {
  LibraryService({
    required DocumentRepository documents,
    required BookmarkRepository bookmarks,
    required AppStorage storage,
    required PdfService pdf,
  }) : _documents = documents,
       _bookmarks = bookmarks,
       _storage = storage,
       _pdf = pdf;

  final DocumentRepository _documents;
  final BookmarkRepository _bookmarks;
  final AppStorage _storage;
  final PdfService _pdf;

  DocumentRepository get documents => _documents;
  BookmarkRepository get bookmarks => _bookmarks;

  /// Imports a file the user picked through the system document picker.
  ///
  /// Returns the stored document. Throws [PaperException] for every
  /// user-recoverable case: unsupported format, oversized file, a source that
  /// vanished, or a destination write that failed.
  Future<Document> importFile(PickedFile picked) async {
    final String extension = _extensionOf(picked.name);
    final DocumentFormat format = picked.format;
    if (format == DocumentFormat.unknown) {
      throw PaperException.unsupportedFormat(
        'PaperOS cannot read ${picked.name}. '
        'It currently opens PDF and plain text documents.',
      );
    }
    if (!DocumentFormat.readableExtensions.contains(extension)) {
      throw PaperException.unsupportedFormat(
        'PaperOS recognises ${format.label} but does not open it yet.',
      );
    }
    if (picked.byteSize > PaperConfig.maxImportBytes) {
      throw PaperException.unsupportedFormat(
        'That file is larger than ${formatBytes(PaperConfig.maxImportBytes)}. '
        'PaperOS will not import it.',
      );
    }

    final File source = File(picked.path);
    if (!source.existsSync()) {
      throw const PaperException.missingFile(
        'That file is no longer where it was. Try importing it again.',
      );
    }

    // Re-importing the same source is a no-op, not a duplicate.
    if (picked.sourceUri != null) {
      final Document? existing = await _documents.findBySourceUri(
        picked.sourceUri!,
      );
      if (existing != null && File(existing.localPath).existsSync()) {
        return existing;
      }
    }

    final String id = newLocalId();
    final Directory libraryDir = await _storage.library();
    final File destination = File(
      p.join(libraryDir.path, '$id${_extensionOf(picked.name)}'),
    );

    int written;
    try {
      written = await _copyStreaming(source, destination);
    } on PaperException {
      rethrow;
    } on FileSystemException catch (error) {
      throw PaperException.storage(
        'PaperOS could not save that file into your library.',
        cause: error,
      );
    }

    if (written == 0) {
      throw const PaperException.corruptDocument(
        'That file is empty, so there is nothing to read.',
      );
    }

    DocumentStatus status = DocumentStatus.ready;
    int? pageCount;

    if (format == DocumentFormat.pdf) {
      final PdfProbe probe = await probePdf(destination.path);
      if (probe.pageCount > 0) {
        pageCount = probe.pageCount;
      } else if (probe.failure != null) {
        // Keep the file so the user can see and delete it, but mark it so the
        // library shows a warning instead of a page count of zero.
        status = DocumentStatus.unreadable;
      }
    }

    final DateTime now = DateTime.now();
    final Document document = Document(
      id: id,
      localPath: destination.path,
      sourceUri: picked.sourceUri,
      sourceName: picked.name,
      title: stripExtension(picked.name),
      format: format,
      byteSize: written,
      pageCount: pageCount,
      status: status,
      isFavorite: false,
      progress: ReadingProgress(
        position: null,
        maxPage: null,
        pageCount: pageCount ?? 0,
      ),
      addedAt: now,
      lastOpenedAt: null,
      openedSeconds: 0,
    );

    return _documents.insert(document);
  }

  /// Opens a PDF purely to learn its page count, then closes it again.
  ///
  /// Never throws: a failure is returned as [PdfProbe.failure] so that import
  /// can decide what to do rather than aborting the whole flow.
  Future<PdfProbe> probePdf(String path) async {
    if (!_pdf.isSupported) {
      return const PdfProbe(pageCount: 0);
    }
    try {
      final PdfDocumentHandle handle = await _pdf.open(path);
      final int count = handle.pageCount;
      await _pdf.close(handle.handle);
      if (count <= 0) {
        return const PdfProbe(
          pageCount: 0,
          failure: 'This PDF reports zero pages.',
        );
      }
      return PdfProbe(pageCount: count);
    } on PaperException catch (error) {
      return PdfProbe(pageCount: 0, failure: error.message);
    } catch (error) {
      return PdfProbe(pageCount: 0, failure: error.toString());
    }
  }

  /// Removes a document from the library and quarantines its file.
  ///
  /// The row goes first: if the file cannot be moved, the user still has a
  /// consistent library and a stray file in `trash/` that is purged after a
  /// week. The reverse order could leave a row pointing at nothing.
  Future<void> remove(Document document) async {
    await _documents.delete(document.id);
    try {
      await _storage.trashFile(document.localPath);
    } on FileSystemException {
      // Already handled by the row deletion above.
    }
  }

  /// Removes every document, its private copy, its progress and its
  /// bookmarks. Notes and tasks are untouched.
  ///
  /// Files are quarantined rather than unlinked, so a failure part-way through
  /// leaves recoverable data in `trash/` instead of a half-deleted library.
  Future<int> removeAll() async {
    final List<Document> documents = await _documents.list();
    for (final Document document in documents) {
      try {
        await _storage.trashFile(document.localPath);
      } on FileSystemException {
        // The row is deleted regardless: a library that still lists a file the
        // user asked to remove is worse than an orphaned file in trash/.
      }
    }
    await _documents.clear();
    return documents.length;
  }

  /// Re-checks that the file behind [document] still exists and is readable.
  /// Used when a document is opened, because files can be removed by the
  /// system or by another app.
  Future<Document> verifyReadable(Document document) async {
    final File file = File(document.localPath);
    if (!file.existsSync()) {
      final Document marked = document.copyWith(status: DocumentStatus.missing);
      await _documents.update(marked);
      throw const PaperException.missingFile(
        'The file for this document is no longer on the device.',
      );
    }
    return document;
  }

  /// Formats a document for a list row. Pure, so it is unit tested.
  static LibraryEntry present(
    Document document,
    DateTime now, {
    bool showByteSize = true,
  }) {
    final List<String> facts = <String>[document.format.label];

    if (document.status == DocumentStatus.missing) {
      return LibraryEntry(
        document: document,
        primary: document.title,
        secondary: 'File missing from this device',
        progressLine: '',
        showProgress: false,
      );
    }
    if (document.status == DocumentStatus.unreadable) {
      facts.add('Could not be opened');
    } else if (document.pageCount != null && document.pageCount! > 0) {
      facts.add(
        '${document.pageCount} page${document.pageCount == 1 ? '' : 's'}',
      );
    }
    if (showByteSize && document.byteSize > 0) {
      facts.add(formatBytes(document.byteSize));
    }
    if (!document.wasOpened) {
      facts.add('Added ${formatDayMonth(document.addedAt)}');
    }

    final String progressLine = _progressLine(document);
    return LibraryEntry(
      document: document,
      primary: document.title,
      secondary: facts.join(' · '),
      progressLine: progressLine,
      showProgress: progressLine.isNotEmpty,
    );
  }

  static String _progressLine(Document document) {
    final ReadingPosition? position = document.progress.position;
    if (position == null) return '';
    final int pageCount = document.pageCount ?? document.progress.pageCount;
    final List<String> parts = <String>[
      if (position.page != null) 'Page ${position.page}',
      formatPercent(document.progressFraction),
      if (document.lastOpenedAt != null)
        formatRelative(document.lastOpenedAt!, DateTime.now()),
    ];
    if (parts.length == 2 && pageCount > 0 && position.page != null) {
      parts.insert(1, 'of $pageCount');
    }
    return parts.join(' · ');
  }

  static String _extensionOf(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot).toLowerCase();
  }

  /// Copies with a fixed-size buffer so a 400 MB textbook never becomes a
  /// 400 MB allocation.
  static Future<int> _copyStreaming(File source, File destination) async {
    final IOSink sink = destination.openWrite();
    int written = 0;
    try {
      await for (final List<int> chunk in source.openRead()) {
        written += chunk.length;
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return written;
  }
}

/// Result of inspecting a PDF during import.
class PdfProbe {
  const PdfProbe({required this.pageCount, this.failure});

  final int pageCount;

  /// Non-null when the file could not be opened. Deliberately not an exception
  /// so that import can keep the file and flag it.
  final String? failure;
}
