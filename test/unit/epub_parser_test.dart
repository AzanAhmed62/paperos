import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/features/reader/epub/epub_book.dart';
import 'package:paperos/features/reader/epub/epub_parser.dart';

import '../support/epub_fixture.dart';

void main() {
  group('EpubParser EPUB 3', () {
    test('reads metadata, nested navigation and safe text', () {
      final EpubParseResult result = const EpubParser().parseBytes(
        buildEpubFixture(),
      );
      final EpubBook book = result.book;

      expect(book.metadata.title, 'A Test Book');
      expect(book.metadata.author, 'Ada Lovelace');
      expect(book.metadata.publisher, 'Paper Press');
      expect(book.metadata.language, 'en');
      expect(book.metadata.identifier, 'urn:test:epub3');
      expect(book.metadata.description, 'A compact fixture.');

      expect(book.chapters, hasLength(2));
      expect(book.chapters.first.title, 'Chapter One');
      expect(book.chapters.last.title, 'Chapter Two');
      expect(book.text, contains('Alpha bravo charlie.'));
      expect(book.text, contains('Foxtrot golf hotel.'));
      expect(book.text, isNot(contains('SCRIPT_SHOULD_NOT_APPEAR')));
      expect(book.text, isNot(contains('Hidden title')));
      expect(book.text, isNot(contains('body { color')));

      expect(book.toc, hasLength(2));
      expect(book.toc.first.title, 'Chapter One');
      expect(book.toc.first.depth, 0);
      expect(book.toc.first.children, hasLength(1));
      expect(book.toc.first.children.first.title, 'A Deep Section');
      expect(book.toc.first.children.first.depth, 1);
      expect(book.toc.last.title, 'Chapter Two');

      final EpubChapter first = book.chapters.first;
      expect(first.anchorOffsets.keys, containsAll(<String>['start', 'deep']));
      expect(
        first.anchorOffsets['deep'],
        greaterThan(first.anchorOffsets['start']!),
      );

      expect(result.coverExtension, 'png');
      expect(result.coverBytes, isNotNull);
    });

    test('finds passages and recovers an annotation anchor', () {
      final EpubBook book = const EpubParser()
          .parseBytes(buildEpubFixture())
          .book;
      final List<EpubSearchResult> results = book.search('repeated phrase');
      expect(results, hasLength(2));
      expect(results.first.chapterTitle, 'Chapter One');
      expect(results.first.locator.spineIndex, 0);
      expect(results.first.excerpt, contains('Repeated phrase'));

      final EpubLocator locator = book.locatorAt(results.first.globalOffset);
      expect(
        book.resolveAnchor(locator.toString()),
        results.first.globalOffset,
      );
      expect(
        book.resolveAnchor(
          'epub:spine=0;char=999999',
          excerpt: 'Repeated phrase',
        ),
        isNotNull,
      );
      expect(book.resolveAnchor('not-a-locator'), isNull);
    });
  });

  group('EpubParser EPUB 2', () {
    test('reads the NCX table of contents and keeps nested entries', () {
      final EpubBook book = const EpubParser()
          .parseBytes(buildEpubFixture(epub2: true))
          .book;

      expect(book.metadata.title, 'A Test Book');
      expect(book.metadata.author, 'Ada Lovelace');
      expect(book.toc, hasLength(2));
      expect(book.toc.first.title, 'Chapter One');
      expect(book.toc.first.children.single.title, 'A Deep Section');
      expect(book.toc.first.children.single.depth, 1);
      expect(book.toc.last.title, 'Chapter Two');
      expect(book.text, contains('Kilo lima mike.'));
    });
  });

  group('EpubParser safety', () {
    test('rejects random bytes instead of guessing at a book', () {
      expect(
        () => const EpubParser().parseBytes(
          Uint8List.fromList(utf8.encode('not a zip archive')),
        ),
        throwsA(isA<EpubParseException>()),
      );
    });

    test('rejects a declared non-EPUB type marker', () {
      expect(
        () => const EpubParser().parseBytes(
          buildEpubFixture(overrideMimetype: 'application/zip'),
        ),
        throwsA(
          isA<EpubParseException>().having(
            (EpubParseException error) => error.message,
            'message',
            contains('not an EPUB'),
          ),
        ),
      );
    });

    test('rejects an unsafe path before opening any content', () {
      final Archive archive = Archive()
        ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
        ..addFile(ArchiveFile.string('../outside.xhtml', '<p>nope</p>'));
      final Uint8List bytes = ZipEncoder().encodeBytes(archive);
      expect(
        () => const EpubParser().parseBytes(bytes),
        throwsA(
          isA<EpubParseException>().having(
            (EpubParseException error) => error.message,
            'message',
            contains('unsafe file path'),
          ),
        ),
      );
    });

    test('rejects a zip entry that declares an unbounded size', () {
      final Archive archive = Archive()
        ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
        ..addFile(ArchiveFile('huge.bin', 33 * 1024 * 1024, <int>[65]));
      final Uint8List bytes = ZipEncoder().encodeBytes(archive);
      expect(
        () => const EpubParser().parseBytes(bytes),
        throwsA(
          isA<EpubParseException>().having(
            (EpubParseException error) => error.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    });

    test('reports a package with no reading order honestly', () {
      final Archive archive = Archive()
        ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
        ..addFile(
          ArchiveFile.string('META-INF/container.xml', '''<?xml version="1.0"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>'''),
        )
        ..addFile(
          ArchiveFile.string('content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Empty</dc:title></metadata>
  <manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine></spine>
</package>'''),
        )
        ..addFile(
          ArchiveFile.string(
            'one.xhtml',
            '<html><body><p>Unused</p></body></html>',
          ),
        );
      expect(
        () => const EpubParser().parseBytes(ZipEncoder().encodeBytes(archive)),
        throwsA(
          isA<EpubParseException>().having(
            (EpubParseException error) => error.message,
            'message',
            contains('no reading order'),
          ),
        ),
      );
    });

    test('keeps an image-only spine item as an honest placeholder', () {
      final Archive archive = Archive()
        ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
        ..addFile(
          ArchiveFile.string('META-INF/container.xml', '''<?xml version="1.0"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>'''),
        )
        ..addFile(
          ArchiveFile.string('content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Pictures</dc:title></metadata>
  <manifest><item id="page" href="page.png" media-type="image/png"/></manifest>
  <spine><itemref idref="page"/></spine>
</package>'''),
        )
        ..addFile(ArchiveFile.string('page.png', 'not really an image'));
      final EpubBook book = const EpubParser()
          .parseBytes(ZipEncoder().encodeBytes(archive))
          .book;
      expect(book.chapters, hasLength(1));
      expect(book.chapters.single.text, contains('no extractable text'));
    });
  });
}
