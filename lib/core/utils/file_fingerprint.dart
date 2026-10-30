import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// SHA-256 fingerprint of a file, computed in a stream.
///
/// Used to recognise a re-imported document when the picker hands back a
/// different `content://` URI, and to prove that a revived row still points at
/// the same bytes. The calculation is deliberately streaming so a large PDF or
/// EPUB never becomes one giant allocation.
Future<String?> fileFingerprint(File file) async {
  if (!file.existsSync()) return null;
  try {
    final Digest digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  } on FileSystemException {
    return null;
  } catch (_) {
    return null;
  }
}
