import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/platform/pdf_service.dart';
import 'package:paperos/features/reader/domain/reader_backend.dart';

/// Records close calls without touching a device channel.
class _RecordingPdfService implements PdfService {
  int closeCalls = 0;
  String? closedHandle;

  @override
  bool get isSupported => true;

  @override
  Future<PdfDocumentHandle> open(String path) async {
    throw UnimplementedError();
  }

  @override
  Future<PdfPageImage> renderPage(
    String handle,
    int pageIndex, {
    int widthPx = 1080,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> close(String handle) async {
    closeCalls++;
    closedHandle = handle;
  }
}

void main() {
  const PdfDocumentHandle handle = PdfDocumentHandle(
    handle: 'native-1',
    pageCount: 3,
    pageWidthPt: 612,
    pageHeightPt: 792,
  );

  test('dispose closes the native PDF handle exactly once', () async {
    final _RecordingPdfService pdf = _RecordingPdfService();
    final PdfReaderBackend backend = PdfReaderBackend(handle, pdf);

    await backend.dispose();
    await backend.dispose();

    expect(pdf.closeCalls, 1);
    expect(pdf.closedHandle, 'native-1');
  });

  test('PDF navigation stays inside the document', () async {
    final PdfReaderBackend backend = PdfReaderBackend(
      handle,
      _RecordingPdfService(),
    );

    expect(backend.pageIndex, 0);
    expect(await backend.next(), isTrue);
    expect(backend.pageIndex, 1);
    await backend.goToPage(999);
    expect(backend.pageIndex, 2);
    expect(await backend.next(), isFalse);
    expect(await backend.previous(), isTrue);
    expect(backend.pageIndex, 1);
    expect(backend.positionLabel, 'Page 2 of 3');
    expect(backend.progress, closeTo(2 / 3, 0.0001));
  });
}
