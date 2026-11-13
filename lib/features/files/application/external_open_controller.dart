import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../library/application/library_providers.dart';
import '../../library/domain/document.dart';
import '../domain/browsed_entry.dart';

/// Turns "Open with PaperOS" intents into a library entry and a reader.
///
/// A VIEW intent carried by the activity is not a file path PaperOS can read;
/// it is a content uri plus a one-shot grant. The document is therefore copied
/// into the library exactly like a picked or browsed file, and only then opened.
///
/// Held alive for the whole app by being read once from the widget tree.
class ExternalOpenController extends Notifier<int> {
  @override
  int build() {
    ref.read(fileBrowserServiceProvider).onExternalDocument(_receive);
    // A cold start delivers the intent before the channel handler exists, so
    // drain whatever the native side stashed.
    scheduleMicrotask(drainPending);
    return 0;
  }

  /// Collects any `ACTION_VIEW` document the platform is holding.
  ///
  /// Safe to call repeatedly: a cold start calls it once, and every resume
  /// calls it again so an intent delivered while backgrounded is not lost.
  Future<void> drainPending() async {
    try {
      final ExternalDocument? document = await ref
          .read(fileBrowserServiceProvider)
          .takeExternalDocument();
      if (document != null) await _receive(document);
    } catch (error) {
      debugPrint('PaperOS: could not read the incoming document: $error');
    }
  }

  Future<void> _receive(ExternalDocument document) async {
    final String name = document.name ?? _nameForMime(document.mimeType);
    final BrowsedEntry entry = BrowsedEntry(
      uri: document.uri,
      name: name,
      isDirectory: false,
      mimeType: document.mimeType,
    );

    final Document? imported = await ref
        .read(importControllerProvider.notifier)
        .importBrowsedEntry(entry);
    if (imported != null) {
      state = state + 1;
      ref.read(appRouterProvider).push(Routes.readerPath(imported.id));
    }
  }

  static String _nameForMime(String? mimeType) {
    switch (mimeType) {
      case 'application/pdf':
        return 'document.pdf';
      case 'text/plain':
        return 'document.txt';
      default:
        return 'document';
    }
  }
}

final externalOpenControllerProvider =
    NotifierProvider<ExternalOpenController, int>(ExternalOpenController.new);
