import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../../config/app_config.dart';
import 'epub_book.dart';

/// A user-recoverable EPUB parse failure.
class EpubParseException implements Exception {
  const EpubParseException(this.message);

  final String message;

  @override
  String toString() => 'EpubParseException: $message';
}

/// Result of opening an EPUB for import or reading.
class EpubParseResult {
  const EpubParseResult({
    required this.book,
    this.coverBytes,
    this.coverExtension,
  });

  final EpubBook book;
  final Uint8List? coverBytes;
  final String? coverExtension;
}

/// A small, deliberately bounded EPUB 2/3 parser.
///
/// PaperOS does not render EPUB HTML or execute scripts. It reads the package
/// document, resolves the spine and navigation document, and reduces each XHTML
/// chapter to plain text. That makes selection, highlights, search and stable
/// character locators tractable on e-ink without a WebView, a JavaScript
/// runtime, or network access.
///
/// This is not a browser and does not claim to reproduce publisher CSS,
/// images, ruby, MathML or scripting. Unsupported publications are reported
/// honestly instead of being displayed as a blank page.
class EpubParser {
  const EpubParser();

  EpubParseResult parseFile(String path) {
    final File file = File(path);
    if (!file.existsSync()) {
      throw const EpubParseException('The EPUB file is no longer on disk.');
    }
    final int length = file.lengthSync();
    if (length <= 0) {
      throw const EpubParseException('This EPUB is empty.');
    }
    if (length > PaperConfig.maxEpubBytes) {
      throw const EpubParseException(
        'This EPUB is too large for the secure reader. '
        'PaperOS opens EPUB files up to 64 MB.',
      );
    }
    final Uint8List bytes;
    try {
      bytes = file.readAsBytesSync();
    } on FileSystemException {
      throw const EpubParseException('PaperOS could not read this EPUB.');
    }
    return parseBytes(bytes);
  }

  EpubParseResult parseBytes(List<int> bytes) {
    final Uint8List data = bytes is Uint8List
        ? bytes
        : Uint8List.fromList(bytes);
    if (data.isEmpty) {
      throw const EpubParseException('This EPUB is empty.');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(data);
    } catch (_) {
      throw const EpubParseException(
        'This file is not a readable EPUB archive.',
      );
    }
    try {
      return _parseArchive(archive);
    } finally {
      archive.clearSync();
    }
  }

  EpubParseResult _parseArchive(Archive archive) {
    _validateArchive(archive);
    _validateMimetype(archive);

    final String containerPath = _findContainerPath(archive);
    final String opfPath = _findPackagePath(archive, containerPath);
    final String opfText = _readUtf8(
      archive,
      opfPath,
      maxBytes: 8 * 1024 * 1024,
    );
    final XmlDocument opf;
    try {
      opf = XmlDocument.parse(opfText);
    } on XmlException {
      throw const EpubParseException('The EPUB package document is malformed.');
    }

    final String opfDir = p.posix.dirname(opfPath);
    final List<_ManifestItem> manifest = _readManifest(opf, opfDir);
    if (manifest.isEmpty) {
      throw const EpubParseException('The EPUB has no declared contents.');
    }
    final List<_SpineItem> spine = _readSpine(opf, manifest);
    if (spine.isEmpty) {
      throw const EpubParseException('The EPUB has no reading order.');
    }

    final EpubMetadata metadata = _readMetadata(opf);
    final _Cover? cover = _readCover(archive, opf, manifest);
    final List<_RawTocEntry> rawToc = _readNavigation(archive, opf, manifest);

    final Map<String, int> spineIndexByPath = <String, int>{
      for (int i = 0; i < spine.length; i++) spine[i].item.path: i,
    };
    final Map<String, String> tocTitleByPath = <String, String>{};
    for (final _RawTocEntry entry in rawToc) {
      tocTitleByPath.putIfAbsent(entry.path, () => entry.title);
    }

    final List<EpubChapter> chapters = <EpubChapter>[];
    int textLength = 0;
    for (int i = 0; i < spine.length; i++) {
      final _ManifestItem item = spine[i].item;
      if (!_isHtmlMediaType(item.mediaType) && !_looksHtml(item.path)) {
        // Image-only spine items are not silently turned into fake prose.
        // Keeping a small honest placeholder preserves the spine index used by
        // existing locators without pretending the image was read.
        chapters.add(
          EpubChapter(
            index: i,
            href: item.path,
            title: _titleFor(
              item,
              i,
              tocTitleByPath[item.path],
              fallback: _fileStem(item.path),
            ),
            text: '[This spine item has no extractable text.]',
            start: 0,
            bodyStart: 0,
            end: 0,
            anchorOffsets: const <String, int>{},
          ),
        );
        continue;
      }

      final _ExtractedText extracted;
      try {
        final String html = _readUtf8(
          archive,
          item.path,
          maxBytes: PaperConfig.maxEpubEntryBytes,
        );
        extracted = _extractText(html);
      } catch (_) {
        chapters.add(
          EpubChapter(
            index: i,
            href: item.path,
            title: _titleFor(
              item,
              i,
              tocTitleByPath[item.path],
              fallback: _fileStem(item.path),
            ),
            text: '[This chapter could not be read.]',
            start: 0,
            bodyStart: 0,
            end: 0,
            anchorOffsets: const <String, int>{},
          ),
        );
        continue;
      }

      textLength += extracted.text.length;
      if (textLength > PaperConfig.maxEpubTextChars) {
        throw const EpubParseException(
          'This EPUB contains more text than PaperOS can open safely.',
        );
      }
      final String heading = extracted.heading;
      final String title = _titleFor(
        item,
        i,
        tocTitleByPath[item.path],
        fallback: heading.isNotEmpty ? heading : _fileStem(item.path),
      );
      chapters.add(
        EpubChapter(
          index: i,
          href: item.path,
          title: title,
          text: extracted.text,
          start: 0,
          bodyStart: 0,
          end: 0,
          anchorOffsets: extracted.anchors,
        ),
      );
    }

    final List<EpubTocEntry> toc = _resolveToc(
      rawToc,
      spineIndexByPath,
      chapters,
    );
    final List<EpubTocEntry> finalToc = toc.isEmpty
        ? <EpubTocEntry>[
            for (final EpubChapter chapter in chapters)
              EpubTocEntry(
                title: chapter.title,
                chapterIndex: chapter.index,
                charOffset: 0,
                depth: 0,
              ),
          ]
        : toc;

    final EpubBook book = EpubBook(
      metadata: metadata,
      chapters: chapters,
      toc: finalToc,
    );
    if (book.text.trim().isEmpty) {
      throw const EpubParseException(
        'This EPUB contains no readable text. '
        'PaperOS does not display image-only or script-driven books.',
      );
    }
    return EpubParseResult(
      book: book,
      coverBytes: cover?.bytes,
      coverExtension: cover?.extension,
    );
  }

  // ------------------------------------------------------------- validation

  void _validateArchive(Archive archive) {
    if (archive.numberOfFiles() > PaperConfig.maxEpubEntries) {
      throw const EpubParseException(
        'This EPUB contains too many files to open safely.',
      );
    }
    int total = 0;
    for (final ArchiveFile file in archive) {
      if (file.isDirectory) continue;
      if (file.isSymbolicLink) {
        throw const EpubParseException(
          'This EPUB contains an unsafe symbolic link.',
        );
      }
      if (file.size < 0 || file.size > PaperConfig.maxEpubEntryBytes) {
        throw const EpubParseException(
          'A file inside this EPUB is too large to open safely.',
        );
      }
      total += file.size;
      if (total > PaperConfig.maxEpubUncompressedBytes) {
        throw const EpubParseException(
          'This EPUB expands to more data than PaperOS can open safely.',
        );
      }
      final String name = file.name.replaceAll('\\', '/');
      if (name.startsWith('/') ||
          name.split('/').contains('..') ||
          name.trim().isEmpty) {
        throw const EpubParseException(
          'This EPUB contains an unsafe file path.',
        );
      }
    }
  }

  void _validateMimetype(Archive archive) {
    final ArchiveFile? mimetype = _find(archive, 'mimetype');
    if (mimetype == null) return;
    final Uint8List? bytes = _bytes(mimetype);
    if (bytes == null) {
      throw const EpubParseException('The EPUB type marker is unreadable.');
    }
    final String text = ascii.decode(bytes, allowInvalid: true).trim();
    if (text.isNotEmpty && text != 'application/epub+zip') {
      throw const EpubParseException(
        'This file is not an EPUB, despite its extension.',
      );
    }
  }

  String _findContainerPath(Archive archive) {
    final ArchiveFile? container = _find(archive, 'META-INF/container.xml');
    if (container != null) {
      final String text = _decode(container);
      try {
        final XmlDocument doc = XmlDocument.parse(text);
        for (final XmlElement element
            in doc.descendants.whereType<XmlElement>()) {
          if (element.name.local != 'rootfile') continue;
          final String? fullPath = _attr(element, 'full-path');
          if (fullPath != null && fullPath.trim().isNotEmpty) {
            return _normalisePath(fullPath.trim());
          }
        }
      } on XmlException {
        // Fall through to a package search. Many real-world EPUBs have a
        // container that is technically broken but a perfectly valid OPF.
      }
    }
    for (final ArchiveFile file in archive) {
      if (file.isDirectory) continue;
      final String name = _normalisePath(file.name);
      if (name.toLowerCase().endsWith('.opf')) return name;
    }
    throw const EpubParseException(
      'This EPUB does not contain a package document.',
    );
  }

  String _findPackagePath(Archive archive, String containerPath) {
    if (_find(archive, containerPath) != null) return containerPath;
    for (final ArchiveFile file in archive) {
      if (!file.isDirectory && file.name.toLowerCase().endsWith('.opf')) {
        return _normalisePath(file.name);
      }
    }
    throw const EpubParseException(
      'The EPUB package document is missing from the archive.',
    );
  }

  // ------------------------------------------------------------- package data

  List<_ManifestItem> _readManifest(XmlDocument opf, String opfDir) {
    final List<_ManifestItem> items = <_ManifestItem>[];
    for (final XmlElement element in opf.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'item') continue;
      final String? id = _attr(element, 'id');
      final String? href = _attr(element, 'href');
      if (id == null || href == null || href.trim().isEmpty) continue;
      final String path = _resolvePath(opfDir, href);
      if (path.isEmpty) continue;
      items.add(
        _ManifestItem(
          id: id,
          path: path,
          mediaType: (_attr(element, 'media-type') ?? '').toLowerCase(),
          properties: (_attr(element, 'properties') ?? '').toLowerCase(),
        ),
      );
    }
    return items;
  }

  List<_SpineItem> _readSpine(XmlDocument opf, List<_ManifestItem> manifest) {
    final Map<String, _ManifestItem> byId = <String, _ManifestItem>{
      for (final _ManifestItem item in manifest) item.id: item,
    };
    final List<_SpineItem> spine = <_SpineItem>[];
    for (final XmlElement element in opf.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'itemref') continue;
      final String? idref = _attr(element, 'idref');
      if (idref == null) continue;
      final _ManifestItem? item = byId[idref];
      if (item == null) continue;
      if ((_attr(element, 'linear') ?? 'yes').toLowerCase() == 'no') {
        continue;
      }
      spine.add(_SpineItem(item));
    }
    return spine;
  }

  EpubMetadata _readMetadata(XmlDocument opf) {
    final Map<String, XmlElement> values = <String, XmlElement>{};
    for (final XmlElement element in opf.descendants.whereType<XmlElement>()) {
      switch (element.name.local) {
        case 'title':
        case 'creator':
        case 'publisher':
        case 'language':
        case 'identifier':
        case 'description':
          values.putIfAbsent(element.name.local, () => element);
      }
    }
    String? text(String local) {
      final XmlElement? element = values[local];
      if (element == null) return null;
      final String value = _textOf(element)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return value.isEmpty ? null : value;
    }

    final List<String> creators = <String>[
      for (final XmlElement element in opf.descendants.whereType<XmlElement>())
        if (element.name.local == 'creator')
          _textOf(element).replaceAll(RegExp(r'\s+'), ' ').trim(),
    ].where((String value) => value.isNotEmpty).toSet().toList(growable: false);

    return EpubMetadata(
      title: text('title'),
      author: creators.isEmpty ? null : creators.join(', '),
      publisher: text('publisher'),
      language: text('language'),
      identifier: text('identifier'),
      description: text('description'),
    );
  }

  _Cover? _readCover(
    Archive archive,
    XmlDocument opf,
    List<_ManifestItem> manifest,
  ) {
    String? coverId;
    for (final XmlElement element in opf.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'meta') continue;
      if ((_attr(element, 'name') ?? '').toLowerCase() != 'cover') continue;
      coverId = _attr(element, 'content');
    }
    _ManifestItem? item;
    for (final _ManifestItem candidate in manifest) {
      if (coverId != null && candidate.id == coverId) {
        item = candidate;
        break;
      }
      if (candidate.properties.split(RegExp(r'\s+')).contains('cover-image')) {
        item = candidate;
        break;
      }
    }
    if (item == null) return null;
    final ArchiveFile? file = _find(archive, item.path);
    if (file == null || file.size > PaperConfig.maxEpubCoverBytes) return null;
    final Uint8List? bytes = _bytes(file);
    if (bytes == null || bytes.isEmpty) return null;
    final String? extension = _imageExtension(item.path, item.mediaType);
    if (extension == null) return null;
    return _Cover(bytes: bytes, extension: extension);
  }

  // ------------------------------------------------------------------- TOC

  List<_RawTocEntry> _readNavigation(
    Archive archive,
    XmlDocument opf,
    List<_ManifestItem> manifest,
  ) {
    _ManifestItem? navItem;
    for (final _ManifestItem item in manifest) {
      if (item.properties.split(RegExp(r'\s+')).contains('nav')) {
        navItem = item;
        break;
      }
    }
    if (navItem != null) {
      final List<_RawTocEntry> entries = _parseNav(
        archive,
        navItem.path,
        p.posix.dirname(navItem.path),
      );
      if (entries.isNotEmpty) return entries;
    }

    String? tocId;
    for (final XmlElement element in opf.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'spine') {
        tocId = _attr(element, 'toc');
      }
    }
    _ManifestItem? ncxItem;
    for (final _ManifestItem item in manifest) {
      if ((tocId != null && item.id == tocId) ||
          item.mediaType == 'application/x-dtbncx+xml') {
        ncxItem = item;
        break;
      }
    }
    if (ncxItem != null) {
      final List<_RawTocEntry> entries = _parseNcx(
        archive,
        ncxItem.path,
        p.posix.dirname(ncxItem.path),
      );
      if (entries.isNotEmpty) return entries;
    }
    return const <_RawTocEntry>[];
  }

  List<_RawTocEntry> _parseNav(
    Archive archive,
    String navPath,
    String baseDir,
  ) {
    final ArchiveFile? file = _find(archive, navPath);
    if (file == null) return const <_RawTocEntry>[];
    final String source = _decode(file);
    try {
      final XmlDocument doc = XmlDocument.parse(source);
      XmlElement? nav;
      for (final XmlElement element
          in doc.descendants.whereType<XmlElement>()) {
        if (element.name.local != 'nav') continue;
        final String type = _attr(element, 'type') ?? '';
        if (nav == null || type.split(RegExp(r'\s+')).contains('toc')) {
          nav = element;
        }
      }
      if (nav == null) return const <_RawTocEntry>[];
      XmlElement? list;
      for (final XmlElement child in nav.descendants.whereType<XmlElement>()) {
        if (child.name.local == 'ol') {
          list = child;
          break;
        }
      }
      if (list == null) return const <_RawTocEntry>[];
      return _parseNavList(list, baseDir, 0);
    } on XmlException {
      return const <_RawTocEntry>[];
    }
  }

  List<_RawTocEntry> _parseNavList(XmlElement list, String baseDir, int depth) {
    final List<_RawTocEntry> entries = <_RawTocEntry>[];
    for (final XmlElement item in list.children.whereType<XmlElement>()) {
      if (item.name.local != 'li') continue;
      XmlElement? link;
      XmlElement? nested;
      for (final XmlElement child in item.children.whereType<XmlElement>()) {
        if (child.name.local == 'a' && link == null) link = child;
        if (child.name.local == 'ol') nested = child;
      }
      final XmlElement? source = link;
      if (source != null) {
        final String title = _textOf(source)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final String? href = _attr(source, 'href');
        final _Target? target = _resolveTarget(baseDir, href);
        if (title.isNotEmpty && target != null) {
          final List<_RawTocEntry> children = nested == null
              ? const <_RawTocEntry>[]
              : _parseNavList(nested, baseDir, depth + 1);
          entries.add(
            _RawTocEntry(
              title: title,
              path: target.path,
              fragment: target.fragment,
              depth: depth,
              children: children,
            ),
          );
        }
      } else if (nested != null) {
        entries.addAll(_parseNavList(nested, baseDir, depth));
      }
    }
    return entries;
  }

  List<_RawTocEntry> _parseNcx(
    Archive archive,
    String ncxPath,
    String baseDir,
  ) {
    final ArchiveFile? file = _find(archive, ncxPath);
    if (file == null) return const <_RawTocEntry>[];
    try {
      final XmlDocument doc = XmlDocument.parse(_decode(file));
      final List<XmlElement> roots = doc.descendants
          .whereType<XmlElement>()
          .where(
            (XmlElement element) =>
                element.name.local == 'navPoint' &&
                !(element.parent is XmlElement &&
                    (element.parent! as XmlElement).name.local == 'navPoint'),
          )
          .toList(growable: false);
      if (roots.isEmpty) return const <_RawTocEntry>[];
      final List<_RawTocEntry> result = <_RawTocEntry>[];
      for (final XmlElement root in roots) {
        result.addAll(_parseNcxPoint(root, baseDir, 0));
      }
      return result;
    } on XmlException {
      return const <_RawTocEntry>[];
    }
  }

  List<_RawTocEntry> _parseNcxPoint(
    XmlElement element,
    String baseDir,
    int depth,
  ) {
    String title = '';
    String? src;
    for (final XmlElement child in element.children.whereType<XmlElement>()) {
      if (child.name.local == 'navLabel') {
        for (final XmlElement label
            in child.descendants.whereType<XmlElement>()) {
          if (label.name.local == 'text') {
            title = _textOf(label).trim();
            break;
          }
        }
      }
      if (child.name.local == 'content') src = _attr(child, 'src');
    }
    final List<_RawTocEntry> children = <_RawTocEntry>[];
    for (final XmlElement child in element.children.whereType<XmlElement>()) {
      if (child.name.local == 'navPoint') {
        children.addAll(_parseNcxPoint(child, baseDir, depth + 1));
      }
    }
    final _Target? target = _resolveTarget(baseDir, src);
    if (title.isEmpty || target == null) return children;
    return <_RawTocEntry>[
      _RawTocEntry(
        title: title,
        path: target.path,
        fragment: target.fragment,
        depth: depth,
        children: children,
      ),
    ];
  }

  List<EpubTocEntry> _resolveToc(
    List<_RawTocEntry> raw,
    Map<String, int> spineIndexByPath,
    List<EpubChapter> chapters,
  ) {
    final Map<int, EpubChapter> byIndex = <int, EpubChapter>{
      for (final EpubChapter chapter in chapters) chapter.index: chapter,
    };
    final List<EpubTocEntry> result = <EpubTocEntry>[];
    for (final _RawTocEntry entry in raw) {
      final int? chapterIndex = spineIndexByPath[entry.path];
      final List<EpubTocEntry> children = _resolveToc(
        entry.children,
        spineIndexByPath,
        chapters,
      );
      if (chapterIndex != null) {
        final EpubChapter? chapter = byIndex[chapterIndex];
        final int offset = entry.fragment.isEmpty
            ? 0
            : (chapter?.anchorOffsets[entry.fragment] ?? 0);
        result.add(
          EpubTocEntry(
            title: entry.title,
            chapterIndex: chapterIndex,
            charOffset: offset,
            depth: entry.depth,
            children: children,
          ),
        );
      } else {
        result.addAll(children);
      }
    }
    return result;
  }

  // --------------------------------------------------------------- text

  _ExtractedText _extractText(String source) {
    XmlDocument? doc;
    try {
      doc = XmlDocument.parse(source);
    } on XmlException {
      return _extractLooseHtml(source);
    }
    XmlElement? body;
    for (final XmlElement element in doc.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'body') {
        body = element;
        break;
      }
    }
    body ??= doc.rootElement;
    final _TextBuilder builder = _TextBuilder();
    String? heading;
    void visit(XmlNode node, {bool pre = false}) {
      if (node is XmlText) {
        builder.addText(node.value, pre: pre);
        return;
      }
      if (node is! XmlElement) return;
      final String tag = node.name.local.toLowerCase();
      if (const <String>{
        'script',
        'style',
        'head',
        'title',
        'nav',
        'svg',
        'math',
        'object',
        'iframe',
      }.contains(tag)) {
        return;
      }
      if (tag == 'br') {
        builder.lineBreak();
        return;
      }
      if (tag == 'img') {
        final String alt = _attr(node, 'alt')?.trim() ?? '';
        if (alt.isNotEmpty) builder.addText(' $alt ', pre: pre);
        return;
      }
      final bool block = const <String>{
        'p',
        'div',
        'section',
        'article',
        'header',
        'footer',
        'blockquote',
        'li',
        'ul',
        'ol',
        'tr',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
        'pre',
      }.contains(tag);
      if (block) builder.startBlock();
      if (tag == 'li') builder.addText('• ');
      final String? id = _attr(node, 'id') ?? _attr(node, 'name');
      if (id != null && id.trim().isNotEmpty) builder.markAnchor(id.trim());
      if (tag == 'h1' || tag == 'h2') {
        if (heading == null || heading!.trim().isEmpty) {
          final String candidate = _textOf(node)
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (candidate.isNotEmpty) heading = candidate;
        }
      }
      for (final XmlNode child in node.children) {
        visit(child, pre: pre || tag == 'pre');
      }
      if (block) builder.endBlock();
    }

    visit(body);
    return _ExtractedText(
      text: builder.finish(),
      heading: heading ?? '',
      anchors: builder.anchors,
    );
  }

  _ExtractedText _extractLooseHtml(String source) {
    String text = source
        .replaceAll(
          RegExp(
            r'<(script|style|head|nav)[^>]*>[\s\S]*?</\1>',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|li|h[1-6]|blockquote|tr)>', caseSensitive: false),
          '\n\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = _decodeEntities(text).replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n[ \t]+'), '\n').trim();
    if (text.isEmpty) {
      throw const EpubParseException('An EPUB chapter has no readable text.');
    }
    return _ExtractedText(
      text: text,
      heading: '',
      anchors: const <String, int>{},
    );
  }

  // -------------------------------------------------------------- helpers

  ArchiveFile? _find(Archive archive, String path) {
    final String normalised = _normalisePath(path);
    for (final ArchiveFile file in archive) {
      if (!file.isDirectory && _normalisePath(file.name) == normalised) {
        return file;
      }
    }
    return null;
  }

  Uint8List? _bytes(ArchiveFile file) {
    if (file.size > PaperConfig.maxEpubEntryBytes) return null;
    try {
      return file.readBytes();
    } catch (_) {
      return null;
    }
  }

  String _readUtf8(Archive archive, String path, {required int maxBytes}) {
    final ArchiveFile? file = _find(archive, path);
    if (file == null) {
      throw EpubParseException('The EPUB is missing $path.');
    }
    if (file.size > maxBytes) {
      throw const EpubParseException('An EPUB document is too large to open.');
    }
    return _decode(file);
  }

  String _decode(ArchiveFile file) {
    final Uint8List? bytes = _bytes(file);
    if (bytes == null) {
      throw const EpubParseException('An EPUB document could not be read.');
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static String _normalisePath(String value) {
    String path = value.replaceAll('\\', '/').trim();
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    path = p.posix.normalize(path);
    if (path == '.' || path.startsWith('../') || path.contains('/../')) {
      return '';
    }
    return path;
  }

  static String _resolvePath(String baseDir, String href) {
    final String raw = href.split('#').first.split('?').first.trim();
    if (raw.isEmpty ||
        raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('data:')) {
      return '';
    }
    String decoded;
    try {
      decoded = Uri.decodeComponent(raw);
    } on ArgumentError {
      decoded = raw;
    }
    final String joined = baseDir.isEmpty
        ? decoded
        : p.posix.join(baseDir, decoded);
    return _normalisePath(joined);
  }

  _Target? _resolveTarget(String baseDir, String? href) {
    if (href == null || href.trim().isEmpty) return null;
    final String trimmed = href.trim();
    if (trimmed.startsWith('http:') ||
        trimmed.startsWith('https:') ||
        trimmed.startsWith('mailto:') ||
        trimmed.startsWith('tel:')) {
      return null;
    }
    final String path = _resolvePath(baseDir, trimmed);
    if (path.isEmpty) return null;
    String fragment = '';
    final int hash = trimmed.indexOf('#');
    if (hash >= 0) {
      fragment = trimmed.substring(hash + 1);
      try {
        fragment = Uri.decodeComponent(fragment);
      } on ArgumentError {
        // Keep the raw fragment.
      }
    }
    return _Target(path: path, fragment: fragment);
  }

  static String _textOf(XmlNode node) {
    final StringBuffer buffer = StringBuffer();
    void walk(XmlNode current) {
      if (current is XmlText) {
        buffer.write(current.value);
      } else if (current is XmlElement) {
        for (final XmlNode child in current.children) {
          walk(child);
        }
      }
    }

    walk(node);
    return buffer.toString();
  }

  static String? _attr(XmlElement element, String localName) {
    for (final XmlAttribute attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  static bool _isHtmlMediaType(String mediaType) =>
      mediaType == 'application/xhtml+xml' ||
      mediaType == 'text/html' ||
      mediaType == 'application/xml' ||
      mediaType == 'text/xml';

  static bool _looksHtml(String path) {
    final String lower = path.toLowerCase();
    return lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm');
  }

  static String _fileStem(String path) {
    final String name = p.posix.basename(path);
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    return stem.isEmpty ? 'Chapter' : stem;
  }

  static String _titleFor(
    _ManifestItem item,
    int index,
    String? tocTitle, {
    required String fallback,
  }) {
    final String? nav = tocTitle?.trim();
    if (nav != null && nav.isNotEmpty) return nav;
    final String stem = fallback.trim();
    if (stem.isNotEmpty) return stem;
    return 'Chapter ${index + 1}';
  }

  static String? _imageExtension(String path, String mediaType) {
    final String lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) {
      return 'jpg';
    }
    if (lowerPath.endsWith('.png')) return 'png';
    if (lowerPath.endsWith('.webp')) return 'webp';
    if (lowerPath.endsWith('.gif')) return 'gif';
    if (mediaType == 'image/jpeg') return 'jpg';
    if (mediaType == 'image/png') return 'png';
    if (mediaType == 'image/webp') return 'webp';
    if (mediaType == 'image/gif') return 'gif';
    return null;
  }

  static String _decodeEntities(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#160;', ' ')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '…')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}

class _ManifestItem {
  const _ManifestItem({
    required this.id,
    required this.path,
    required this.mediaType,
    required this.properties,
  });

  final String id;
  final String path;
  final String mediaType;
  final String properties;
}

class _SpineItem {
  const _SpineItem(this.item);

  final _ManifestItem item;
}

class _Cover {
  const _Cover({required this.bytes, required this.extension});

  final Uint8List bytes;
  final String extension;
}

class _Target {
  const _Target({required this.path, required this.fragment});

  final String path;
  final String fragment;
}

class _RawTocEntry {
  const _RawTocEntry({
    required this.title,
    required this.path,
    required this.fragment,
    required this.depth,
    required this.children,
  });

  final String title;
  final String path;
  final String fragment;
  final int depth;
  final List<_RawTocEntry> children;
}

class _ExtractedText {
  const _ExtractedText({
    required this.text,
    required this.heading,
    required this.anchors,
  });

  final String text;
  final String heading;
  final Map<String, int> anchors;
}

/// Normalises block text without ever inserting a partial UTF-16 character.
class _TextBuilder {
  final StringBuffer _buffer = StringBuffer();
  final Map<String, int> anchors = <String, int>{};
  bool _pendingParagraph = false;
  bool _pendingLine = false;
  bool _pendingSpace = false;
  bool _lastWasSpace = true;

  int get length => _buffer.length;

  void markAnchor(String id) {
    if (anchors.containsKey(id)) return;
    _flushPending();
    anchors[id] = _buffer.length;
  }

  void startBlock() {
    if (_buffer.length > 0) _pendingParagraph = true;
  }

  void endBlock() {
    if (_buffer.length > 0) _pendingParagraph = true;
  }

  void lineBreak() {
    if (_buffer.length > 0) {
      _pendingSpace = false;
      _pendingLine = true;
    }
  }

  void addText(String value, {bool pre = false}) {
    if (value.isEmpty) return;
    if (pre) {
      _flushPending();
      _buffer.write(value);
      _lastWasSpace = RegExp(r'\s$').hasMatch(value);
      return;
    }
    for (final int rune in value.runes) {
      final String character = String.fromCharCode(rune);
      if (character.trim().isEmpty) {
        // A newline inside XHTML is a word separator, not a line break. Block
        // elements and <br> are the only things that create new lines.
        if (!_lastWasSpace) _pendingSpace = true;
        continue;
      }
      _flushPending();
      _buffer.write(character);
      _lastWasSpace = false;
    }
  }

  void _flushPending() {
    if (_pendingParagraph) {
      if (_buffer.length > 0) {
        final String current = _buffer.toString();
        if (!current.endsWith('\n\n')) {
          _buffer.write(current.endsWith('\n') ? '\n' : '\n\n');
        }
      }
      _pendingParagraph = false;
      _pendingLine = false;
      _pendingSpace = false;
      _lastWasSpace = true;
      return;
    }
    if (_pendingLine) {
      if (_buffer.length > 0 && !_buffer.toString().endsWith('\n')) {
        _buffer.write('\n');
      }
      _pendingLine = false;
      _pendingSpace = false;
      _lastWasSpace = true;
      return;
    }
    if (_pendingSpace) {
      if (_buffer.isNotEmpty && !_lastWasSpace) _buffer.write(' ');
      _pendingSpace = false;
      _lastWasSpace = true;
    }
  }

  String finish() {
    _pendingParagraph = false;
    _pendingLine = false;
    _pendingSpace = false;
    final String value = _buffer.toString().trim();
    if (value.isEmpty) return '';
    final int leading =
        _buffer.toString().length - _buffer.toString().trimLeft().length;
    if (leading > 0 && anchors.isNotEmpty) {
      for (final MapEntry<String, int> entry in anchors.entries.toList()) {
        anchors[entry.key] = (entry.value - leading).clamp(0, value.length);
      }
    }
    return value;
  }
}
