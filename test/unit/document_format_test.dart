import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/features/library/domain/document.dart';

void main() {
  group('DocumentFormat', () {
    test('the picker only offers formats this build can open', () {
      expect(
        DocumentFormat.importableExtensions,
        DocumentFormat.readableExtensions,
      );
      expect(
        DocumentFormat.importableExtensions,
        containsAll(<String>['pdf', 'txt', 'text', 'log', 'nfo', 'epub']),
      );
      expect(DocumentFormat.importableExtensions, isNot(contains('md')));
      expect(DocumentFormat.importableExtensions, isNot(contains('docx')));
      expect(DocumentFormat.importableExtensions, isNot(contains('cbz')));
      expect(DocumentFormat.importableExtensions, isNot(contains('html')));
    });

    test('recognises a format without claiming it is readable', () {
      expect(DocumentFormat.fromFileName('notes.docx'), DocumentFormat.word);
      expect(DocumentFormat.isReadable(DocumentFormat.word), isFalse);
      expect(DocumentFormat.isReadable(DocumentFormat.comic), isFalse);
      expect(DocumentFormat.isReadable(DocumentFormat.epub), isTrue);
      expect(DocumentFormat.isReadable(DocumentFormat.pdf), isTrue);
      expect(DocumentFormat.isReadable(DocumentFormat.text), isTrue);
    });

    test('an unknown extension is not silently treated as text', () {
      expect(
        DocumentFormat.fromFileName('archive.unknown'),
        DocumentFormat.unknown,
      );
      expect(
        DocumentFormat.fromFileName('no-extension'),
        DocumentFormat.unknown,
      );
    });
  });
}
