import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../features/files/domain/browsed_entry.dart';
import '../errors/paper_exception.dart';

/// Browsing the folders a user has explicitly handed to PaperOS.
///
/// Android 11+ does not allow an app to read arbitrary files, and PaperOS does
/// not ask for `MANAGE_EXTERNAL_STORAGE` to pretend otherwise. Instead the user
/// grants a folder through the system picker, the grant is persisted, and the
/// Storage Access Framework is what actually lists and reads the contents. This
/// interface is the single seam through which that happens; no widget talks to
/// the platform channel directly.
abstract interface class FileBrowserService {
  /// Whether folder browsing exists on this platform at all.
  bool get isSupported;

  /// Shows the system folder picker. Returns null when the user cancels or the
  /// platform has no picker.
  Future<BrowsedLocation?> pickLocation();

  /// Lists [directoryUri] (a folder), or the root of [treeUri] when it is null.
  Future<List<BrowsedEntry>> listChildren({
    required String treeUri,
    String? directoryUri,
  });

  /// Copies a document the user chose out of the tree into app-private cache
  /// and returns its absolute path, so the existing import pipeline can read it
  /// as an ordinary file.
  Future<String> materialise(BrowsedEntry entry);

  /// Releases the persisted grant for [location]. Best effort.
  Future<void> releaseLocation(BrowsedLocation location);

  /// A document that arrived from an `ACTION_VIEW` intent, or null.
  Future<ExternalDocument?> takeExternalDocument();

  /// Called when the OS delivers a new `ACTION_VIEW` intent while running.
  void onExternalDocument(void Function(ExternalDocument document) handler);
}

class PlatformFileBrowserService implements FileBrowserService {
  const PlatformFileBrowserService({bool? android}) : _android = android;

  /// Overrides the platform check in tests; null means "ask the platform".
  final bool? _android;

  static const MethodChannel _channel = MethodChannel('dev.paperos/files');

  @override
  bool get isSupported => _android ?? Platform.isAndroid;

  @override
  Future<BrowsedLocation?> pickLocation() async {
    if (!isSupported) return null;
    try {
      final Map<Object?, Object?>? map = await _channel
          .invokeMethod<Map<Object?, Object?>>('pickLocation');
      if (map == null) return null;
      final String? uri = map['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;
      return BrowsedLocation(
        // The native side does not know the database id; the caller assigns it.
        id: '',
        uri: uri,
        label: (map['label'] as String?) ?? p.basename(uri),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      throw PaperException.permission(
        error.message ?? 'The folder picker could not be opened.',
        cause: error,
        detail: error.code,
      );
    }
  }

  @override
  Future<List<BrowsedEntry>> listChildren({
    required String treeUri,
    String? directoryUri,
  }) async {
    if (!isSupported) return const <BrowsedEntry>[];
    try {
      final List<Object?>? raw = await _channel.invokeMethod<List<Object?>>(
        'listChildren',
        <String, Object?>{'treeUri': treeUri, 'directoryUri': ?directoryUri},
      );
      if (raw == null) return const <BrowsedEntry>[];
      return raw
          .whereType<Map<Object?, Object?>>()
          .map(BrowsedEntry.fromMap)
          .toList(growable: false);
    } on MissingPluginException {
      return const <BrowsedEntry>[];
    } on PlatformException catch (error) {
      if (error.code == 'access_denied') {
        throw PaperException.permission(
          'PaperOS can no longer read that folder. '
          'The permission may have been revoked — remove and add it again.',
          cause: error,
          detail: error.code,
        );
      }
      throw PaperException.storage(
        error.message ?? 'That folder could not be listed.',
        cause: error,
        detail: error.code,
      );
    }
  }

  @override
  Future<String> materialise(BrowsedEntry entry) async {
    if (!isSupported) {
      throw const PaperException.missingFile(
        'This file cannot be opened on this platform.',
      );
    }
    try {
      final String? path = await _channel.invokeMethod<String>(
        'materialise',
        <String, Object?>{'uri': entry.uri, 'name': entry.name},
      );
      if (path == null || path.isEmpty) {
        throw const PaperException.missingFile(
          'That file could not be read. It may have been moved or deleted.',
        );
      }
      return path;
    } on MissingPluginException {
      throw const PaperException.missingFile(
        'This file cannot be opened on this platform.',
      );
    } on PlatformException catch (error) {
      if (error.code == 'access_denied') {
        throw PaperException.permission(
          'PaperOS is not allowed to read that file any more.',
          cause: error,
          detail: error.code,
        );
      }
      throw PaperException.missingFile(
        error.message ?? 'That file could not be read.',
        cause: error,
        detail: error.code,
      );
    }
  }

  @override
  Future<void> releaseLocation(BrowsedLocation location) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('releaseLocation', <String, Object?>{
        'uri': location.uri,
      });
    } on PlatformException {
      // A grant that cannot be released is not worth interrupting the user for.
    } on MissingPluginException {
      // Nothing to release.
    }
  }

  @override
  Future<ExternalDocument?> takeExternalDocument() async {
    if (!isSupported) return null;
    try {
      final Map<Object?, Object?>? map = await _channel
          .invokeMethod<Map<Object?, Object?>>('takeExternalDocument');
      if (map == null) return null;
      return ExternalDocument.fromMap(map);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  void onExternalDocument(void Function(ExternalDocument document) handler) {
    if (!isSupported) return;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'onExternalDocument') return null;
      final Object? arguments = call.arguments;
      if (arguments is Map<Object?, Object?>) {
        handler(ExternalDocument.fromMap(arguments));
      }
      return null;
    });
  }
}
