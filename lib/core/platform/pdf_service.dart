import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../errors/paper_exception.dart';

/// An opened PDF, as reported by the platform.
class PdfDocumentHandle {
  const PdfDocumentHandle({
    required this.handle,
    required this.pageCount,
    required this.pageWidthPt,
    required this.pageHeightPt,
  });

  final String handle;
  final int pageCount;
  final double pageWidthPt;
  final double pageHeightPt;

  double get aspectRatio =>
      pageHeightPt > 0 ? pageWidthPt / pageHeightPt : 0.7071;
}

/// A single rendered page.
class PdfPageImage {
  const PdfPageImage({
    required this.width,
    required this.height,
    required this.png,
  });

  final int width;
  final int height;
  final Uint8List png;

  double get aspectRatio => height > 0 ? width / height : 0.7071;
}

/// Platform PDF rendering.
///
/// Split into `open` / `renderPage` / `close` rather than handing a live
/// document object across the channel: a channel cannot hold a file
/// descriptor, and an explicit handle makes resource lifetime testable and
/// reviewable.
abstract interface class PdfService {
  bool get isSupported;

  /// Opens [path] (an absolute file path or a `content://` URI).
  ///
  /// Throws [PaperException] of kind `unsupportedFormat` when this build has no
  /// platform renderer, `missingFile` when the file is gone or unreadable, and
  /// `corruptDocument` when the bytes are not a usable PDF.
  Future<PdfDocumentHandle> open(String path);

  /// Rasterises a 0-based page index to PNG bytes at [widthPx].
  Future<PdfPageImage> renderPage(
    String handle,
    int pageIndex, {
    int widthPx = 1080,
  });

  Future<void> close(String handle);
}

/// [PdfService] backed by the Kotlin `PdfRenderChannel`, which wraps Android's
/// own `android.graphics.pdf.PdfRenderer`.
class PlatformPdfService implements PdfService {
  PlatformPdfService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'dev.paperos/pdf';

  final MethodChannel _channel;

  @override
  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<PdfDocumentHandle> open(String path) async {
    if (!isSupported) {
      throw const PaperException.unsupportedFormat(
        'PDF reading needs Android. On this platform, open the file another way.',
      );
    }
    try {
      final Map<Object?, Object?>? reply = await _channel
          .invokeMapMethod<Object?, Object?>('open', <String, Object?>{
            'path': path,
          });
      if (reply == null) {
        throw const PaperException.corruptDocument(
          'This PDF could not be opened.',
        );
      }
      return PdfDocumentHandle(
        handle: reply['handle']! as String,
        pageCount: (reply['pageCount'] as int?) ?? 0,
        pageWidthPt: (reply['pageWidthPt'] as num?)?.toDouble() ?? 0,
        pageHeightPt: (reply['pageHeightPt'] as num?)?.toDouble() ?? 0,
      );
    } on MissingPluginException {
      throw const PaperException.platform(
        'The PDF renderer is not available in this build.',
      );
    } on PlatformException catch (error) {
      throw _map(error, fallback: 'This PDF could not be opened.');
    }
  }

  @override
  Future<PdfPageImage> renderPage(
    String handle,
    int pageIndex, {
    int widthPx = 1080,
  }) async {
    try {
      final Map<Object?, Object?>? reply = await _channel
          .invokeMapMethod<Object?, Object?>('renderPage', <String, Object?>{
            'handle': handle,
            'pageIndex': pageIndex,
            'widthPx': widthPx,
          });
      if (reply == null) {
        throw PaperException.corruptDocument(
          'Page ${pageIndex + 1} could not be drawn.',
        );
      }
      return PdfPageImage(
        width: (reply['width'] as int?) ?? widthPx,
        height: (reply['height'] as int?) ?? 0,
        png: reply['png']! as Uint8List,
      );
    } on MissingPluginException {
      throw const PaperException.platform(
        'The PDF renderer is not available in this build.',
      );
    } on PlatformException catch (error) {
      throw _map(error, fallback: 'Page ${pageIndex + 1} could not be drawn.');
    }
  }

  @override
  Future<void> close(String handle) async {
    try {
      await _channel.invokeMethod<bool>('close', <String, Object?>{
        'handle': handle,
      });
    } on MissingPluginException {
      // Nothing to release.
    } on PlatformException {
      // A failed close must never surface: the OS reclaims the descriptor when
      // the process dies, and the reader is already gone from the UI.
    }
  }

  static PaperException _map(
    PlatformException error, {
    required String fallback,
  }) {
    switch (error.code) {
      case 'missing_file':
        return PaperException.missingFile(
          error.message ?? 'The file for this document is no longer available.',
          cause: error,
        );
      case 'corrupt':
        return PaperException.corruptDocument(
          error.message ?? fallback,
          cause: error,
        );
      case 'out_of_range':
        return PaperException.missingFile(
          error.message ?? fallback,
          cause: error,
        );
      case 'closed':
      case 'unknown_handle':
        return PaperException.storage(error.message ?? fallback, cause: error);
      default:
        return PaperException.platform(error.message ?? fallback, cause: error);
    }
  }
}
