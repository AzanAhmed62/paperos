import 'dart:convert';
import 'dart:math';

final Random _random = Random.secure();

/// Generates a collision-resistant, roughly sortable local id.
///
/// PaperOS has no server and no cross-device sync, so the only requirement is
/// uniqueness within one install plus a rough time ordering (which keeps
/// debug output readable). That is not worth a uuid dependency.
String newLocalId() {
  final List<int> bytes = List<int>.generate(9, (_) => _random.nextInt(256));
  final String stamp = DateTime.now().microsecondsSinceEpoch
      .toRadixString(36)
      .padLeft(11, '0');
  return '$stamp${base64Url.encode(bytes).replaceAll('=', '')}';
}
