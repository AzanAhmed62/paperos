import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
import '../../reader/epub/epub_book.dart';
import '../../reader/epub/epub_parser.dart';
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
    EpubParser epub = const EpubParser(),
  }) : _documents = documents,
       _bookmarks = bookmarks,
       _storage = storage,
       _pdf = pdf,
       _epub = epub;

  final DocumentRepository _documents;
  final BookmarkRepository _bookmarks;
  final AppStorage _storage;
  final PdfService _pdf;
  final EpubParser _epub;

  DocumentRepository get documents => _documents;
  BookmarkRepository get bookmarks => _bookmarks;

  /// Imports a file the user picked through the system document picker.
  ///
  /// A source that was imported before is never turned into a second row. If
  /// its app-private copy was deleted, the existing row is revived instead:
  /// bookmarks, annotations, progress and any user-renamed title survive.
  Future<Document> importFile(PickedFile picked) async {
    final String extension = _extensionOf(picked.name);
    final DocumentFormat format = picked.format;
    if (format == DocumentFormat.unknown) {
      throw PaperException.unsupportedFormat(
        'PaperOS cannot read ${picked.name}. '
        'It currently opens PDF, plain text and EPUB documents.',
      );
    }
    if (!DocumentFormat.readableExtensions.contains(
      extension.replaceFirst('.', ''),
    )) {
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
    final int sourceLength = await source.length();
    if (sourceLength > PaperConfig.maxImportBytes) {
      throw PaperException.unsupportedFormat(
        'That file is larger than ${formatBytes(PaperConfig.maxImportBytes)}. '
        'PaperOS will not import it.',
      );
    }

    // Exact source identity is the cheapest and strongest duplicate check.
    Document? existing = picked.sourceUri == null
        ? null
        : await _documents.findBySourceUri(picked.sourceUri!);
    if (existing != null && File(existing.localPath).existsSync()) {
      return existing;
    }

    final String id = existing?.id ?? newLocalId();
    final Directory libraryDir = await _storage.library();
    final File destination = _destinationFor(
      libraryDir: libraryDir,
      existing: existing,
      id: id,
      extension: extension,
    );
    await destination.parent.create(recursive: true);

    // One read of the source: the bytes are copied to a `.part` file and hashed
    // in the same pass. The finished copy is renamed into place only after the
    // write succeeds, so a failed or interrupted import can never leave a
    // half-written file where a document row expects a complete one.
    final _CopyResult copy;
    try {
      copy = await _copyWithFingerprint(source, destination);
    } on PaperException {
      rethrow;
    } on FileSystemException catch (error) {
      throw PaperException.storage(
        'PaperOS could not save that file into your library.',
        cause: error,
      );
    }

    if (copy.bytes == 0) {
      throw const PaperException.corruptDocument(
        'That file is empty, so there is nothing to read.',
      );
    }

    // Fingerprint duplicate detection happens after the copy because the hash
    // is produced by that same pass. A byte-identical copy of a document that
    // already has a readable file is discarded instead of becoming a second
    // row; a stale row with the same bytes is revived below.
    if (existing == null && copy.fingerprint.isNotEmpty) {
      final Document? duplicate = await _documents.findByFingerprint(
        copy.fingerprint,
      );
      if (duplicate != null) {
        if (File(duplicate.localPath).existsSync()) {
          await _deleteQuietly(destination);
          return duplicate;
        }
        existing = duplicate;
      }
    }
    final String fingerprint = copy.fingerprint;

    DocumentStatus status = DocumentStatus.ready;
    int? pageCount;
    String title = stripExtension(picked.name);
    String? author;
    String? publisher;
    String? language;
    String? identifier;
    String? description;
    String? coverPath = existing?.coverPath;

    if (format == DocumentFormat.pdf) {
      final PdfProbe probe = await probePdf(destination.path);
      if (probe.pageCount > 0) {
        pageCount = probe.pageCount;
      } else if (probe.failure != null) {
        // Keep the file so the user can see and delete it, but mark it so the
        // library shows a warning instead of a page count of zero.
        status = DocumentStatus.unreadable;
      }
    } else if (format == DocumentFormat.epub) {
      final _EpubProbe probe = await _probeEpub(destination.path);
      if (probe.failure != null) {
        status = DocumentStatus.unreadable;
      } else {
        final EpubMetadata metadata = probe.result!.metadata;
        final String? metadataTitle = metadata.title?.trim();
        if (metadataTitle != null && metadataTitle.isNotEmpty) {
          title = metadataTitle;
        }
        author = metadata.author;
        publisher = metadata.publisher;
        language = metadata.language;
        identifier = metadata.identifier;
        description = metadata.description;
        coverPath = await _saveCover(id, probe.result!) ?? existing?.coverPath;
      }
    }

    final String finalFingerprint = fingerprint.isNotEmpty
        ? fingerprint
        : (existing?.fingerprint ?? '');
    if (existing != null) {
      final Document revived = await _documents.relink(
        existing,
        localPath: destination.path,
        sourceUri: picked.sourceUri,
        sourceName: picked.name,
        byteSize: copy.bytes,
        pageCount: pageCount ?? existing.pageCount,
        status: status,
        fingerprint: finalFingerprint,
        title: title,
        author: author,
        publisher: publisher,
        language: language,
        identifier: identifier,
        description: description,
        coverPath: coverPath,
      );
      return revived;
    }

    final DateTime now = DateTime.now();
    final Document document = Document(
      id: id,
      localPath: destination.path,
      sourceUri: picked.sourceUri,
      sourceName: picked.name,
      title: title,
      format: format,
      byteSize: copy.bytes,
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
      author: author,
      publisher: publisher,
      language: language,
      identifier: identifier,
      description: description,
      coverPath: coverPath,
      fingerprint: finalFingerprint.isEmpty ? null : finalFingerprint,
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
    PdfDocumentHandle? handle;
    try {
      handle = await _pdf.open(path);
      final int count = handle.pageCount;
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
    } finally {
      final PdfDocumentHandle? opened = handle;
      if (opened != null) {
        // The probe's only job is the page count; a close failure must not turn
        // a readable document into an import failure. The platform close is
        // still attempted so a successful open never leaks a native handle.
        try {
          await _pdf.close(opened.handle);
        } on Object {
          // Best-effort cleanup; nothing else can be done with this handle.
        }
      }
    }
  }

  Future<_EpubProbe> _probeEpub(String path) async {
    try {
      return _EpubProbe(result: await _epub.probeFileAsync(path));
    } on EpubParseException catch (error) {
      return _EpubProbe(failure: error.message);
    } on PaperException catch (error) {
      return _EpubProbe(failure: error.message);
    } catch (error) {
      return _EpubProbe(failure: 'This EPUB could not be opened.');
    }
  }

  Future<String?> _saveCover(String id, EpubProbeResult result) async {
    final cover = result.coverBytes;
    final String? extension = result.coverExtension;
    if (cover == null || extension == null || cover.isEmpty) return null;
    try {
      final Directory directory = await _storage.covers();
      final File file = File(p.join(directory.path, '$id.$extension'));
      await file.writeAsBytes(cover, flush: true);
      return file.path;
    } on FileSystemException {
      // A missing cover is cosmetic. Never fail an import because of it.
      return null;
    }
  }

  /// Removes a document from the library and quarantines its file.
  ///
  /// The row goes first: if the file cannot be moved, the user still has a
  /// consistent library and a stray file in `trash/` that is purged after a
  /// week. The reverse order could leave a row pointing at nothing.
  Future<void> remove(Document document) async {
    final String? cover = document.coverPath;
    await _documents.delete(document.id);
    try {
      await _storage.trashFile(document.localPath);
    } on FileSystemException {
      // Already handled by the row deletion above.
    }
    if (cover != null) {
      try {
        await _storage.trashFile(cover);
      } on FileSystemException {
        // Cover cleanup is best effort.
      }
    }
  }

  /// Removes every document, its private copy, its progress, its bookmarks and
  /// its annotations. Notes and tasks are untouched.
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
      final String? cover = document.coverPath;
      if (cover != null) {
        try {
          await _storage.trashFile(cover);
        } on FileSystemException {
          // Cover cleanup is best effort.
        }
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
    } else {
      final String? author = document.author?.trim();
      if (author != null && author.isNotEmpty) facts.add(author);
      if (!DocumentFormat.isReflowable(document.format) &&
          document.pageCount != null &&
          document.pageCount! > 0) {
        facts.add(
          '${document.pageCount} page${document.pageCount == 1 ? '' : 's'}',
        );
      }
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
      if (position.page != null &&
          !DocumentFormat.isReflowable(document.format))
        'Page ${position.page}',
      formatPercent(document.progressFraction),
      if (document.lastOpenedAt != null)
        formatRelative(document.lastOpenedAt!, DateTime.now()),
    ];
    if (parts.length == 2 &&
        pageCount > 0 &&
        position.page != null &&
        !DocumentFormat.isReflowable(document.format)) {
      parts.insert(1, 'of $pageCount');
    }
    return parts.join(' · ');
  }

  static String _extensionOf(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot).toLowerCase();
  }

  static File _destinationFor({
    required Directory libraryDir,
    required Document? existing,
    required String id,
    required String extension,
  }) {
    if (existing != null) {
      final File old = File(existing.localPath);
      if (p.equals(p.dirname(old.path), libraryDir.path)) return old;
    }
    return File(p.join(libraryDir.path, '$id$extension'));
  }

  /// Copies and fingerprints in one pass.
  ///
  /// The bytes are written to `<destination>.part`; the hash is fed from the
  /// same chunks. Only a complete copy is renamed over the destination, so an
  /// interrupted write leaves the previous file (when reviving a row) intact
  /// and never exposes a truncated import to the reader.
  static Future<_CopyResult> _copyWithFingerprint(
    File source,
    File destination,
  ) async {
    final File partial = File('${destination.path}.part');
    final _DigestSink digestSink = _DigestSink();
    final ByteConversionSink hasher = sha256.startChunkedConversion(digestSink);
    final IOSink sink = partial.openWrite();
    bool closed = false;
    int written = 0;
    try {
      await for (final List<int> chunk in source.openRead()) {
        written += chunk.length;
        hasher.add(chunk);
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      closed = true;
      hasher.close();
      if (written == 0) return const _CopyResult(bytes: 0, fingerprint: '');
      await partial.rename(destination.path);
      return _CopyResult(
        bytes: written,
        fingerprint: digestSink.value?.toString() ?? '',
      );
    } finally {
      if (!closed) {
        try {
          await sink.close();
        } on Object {
          // The original write error is the one worth reporting.
        }
      }
      // After a successful rename this path no longer exists; on any failure it
      // removes the partial file. `existsSync` avoids a noisy exception.
      await _deleteQuietly(partial);
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Best-effort cleanup. The import error is more useful than this one.
    }
  }
}

/// Result of a one-pass copy and fingerprint.
class _CopyResult {
  const _CopyResult({required this.bytes, required this.fingerprint});

  final int bytes;
  final String fingerprint;
}

/// Collects the single digest produced by [sha256.startChunkedConversion].
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Result of inspecting a PDF during import.
class PdfProbe {
  const PdfProbe({required this.pageCount, this.failure});

  final int pageCount;

  /// Non-null when the file could not be opened. Deliberately not an exception
  /// so that import can keep the file and flag it.
  final String? failure;
}

class _EpubProbe {
  const _EpubProbe({this.result, this.failure});

  final EpubProbeResult? result;
  final String? failure;
}
