import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A tiny, deliberately valid EPUB used by the v1.1 tests.
///
/// The fixture is built in memory so the parser tests exercise the same ZIP and
/// XML paths as an import without checking binary blobs into the repository.
Uint8List buildEpubFixture({
  bool epub2 = false,
  bool includeCover = true,
  bool includeScript = true,
  String? overrideMimetype,
  String title = 'A Test Book',
  String creator = 'Ada Lovelace',
}) {
  final Archive archive = Archive();

  void add(String name, String content) {
    archive.addFile(ArchiveFile.string(name, content));
  }

  void addBytes(String name, List<int> bytes) {
    archive.addFile(ArchiveFile.bytes(name, bytes));
  }

  final String mimetype = overrideMimetype ?? 'application/epub+zip';
  add('mimetype', mimetype);
  add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');

  final String chapterOne =
      '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <title>Hidden title</title>
  <style>body { color: black; }</style>
  ${includeScript ? '<script>window.evil = "SCRIPT_SHOULD_NOT_APPEAR";</script>' : ''}
</head>
<body>
  <h1 id="start">Chapter One</h1>
  <p>Alpha <em>bravo</em> charlie. Delta echo.</p>
  <h2 id="deep">A Deep Section</h2>
  <p>Foxtrot golf hotel. India juliet.</p>
  <p>Repeated phrase for recovery.</p>
  <img src="https://tracker.example/pixel.png" alt="A picture"/>
  <a href="https://example.com/away">external link</a>
</body>
</html>''';

  const String chapterTwo = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Two</title></head>
<body>
  <h1>Chapter Two</h1>
  <p>Kilo lima mike. November oscar papa.</p>
  <p>Repeated phrase for recovery.</p>
</body>
</html>''';

  add('OEBPS/text/ch1.xhtml', chapterOne);
  add('OEBPS/text/ch2.xhtml', chapterTwo);

  if (epub2) {
    add('OEBPS/toc.ncx', '''<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="urn:test:epub2"/></head>
  <docTitle><text>$title</text></docTitle>
  <navMap>
    <navPoint id="n1" playOrder="1">
      <navLabel><text>Chapter One</text></navLabel>
      <content src="text/ch1.xhtml"/>
      <navPoint id="n2" playOrder="2">
        <navLabel><text>A Deep Section</text></navLabel>
        <content src="text/ch1.xhtml#deep"/>
      </navPoint>
    </navPoint>
    <navPoint id="n3" playOrder="3">
      <navLabel><text>Chapter Two</text></navLabel>
      <content src="text/ch2.xhtml"/>
    </navPoint>
  </navMap>
</ncx>''');
    add('OEBPS/content.opf', '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:test:epub2</dc:identifier>
    <dc:title>$title</dc:title>
    <dc:creator>$creator</dc:creator>
    <dc:language>en</dc:language>
    <dc:publisher>Paper Press</dc:publisher>
    <dc:description>A compact fixture.</dc:description>
    ${includeCover ? '<meta name="cover" content="cover-image"/>' : ''}
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    ${includeCover ? '<item id="cover-image" href="images/cover.png" media-type="image/png"/>' : ''}
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>''');
  } else {
    add('OEBPS/nav.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body>
  <nav epub:type="toc">
    <ol>
      <li>
        <a href="text/ch1.xhtml#start">Chapter One</a>
        <ol><li><a href="text/ch1.xhtml#deep">A Deep Section</a></li></ol>
      </li>
      <li><a href="text/ch2.xhtml">Chapter Two</a></li>
    </ol>
  </nav>
</body>
</html>''');
    add('OEBPS/content.opf', '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:test:epub3</dc:identifier>
    <dc:title>$title</dc:title>
    <dc:creator>$creator</dc:creator>
    <dc:language>en</dc:language>
    <dc:publisher>Paper Press</dc:publisher>
    <dc:description>A compact fixture.</dc:description>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    ${includeCover ? '<item id="cover-image" href="images/cover.png" media-type="image/png" properties="cover-image"/>' : ''}
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>''');
  }

  if (includeCover) {
    // 1x1 transparent PNG.
    addBytes(
      'OEBPS/images/cover.png',
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        'YAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
      ),
    );
  }

  return ZipEncoder().encodeBytes(archive);
}
