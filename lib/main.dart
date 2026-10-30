import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/paper_app.dart';
import 'app/providers.dart';

/// Entry point.
///
/// Deliberately thin. It resolves the two things that cannot be built lazily —
/// the shared preferences instance, because settings are read synchronously all
/// over the app — and hands everything else to the provider graph.
///
/// The database is not opened here. `AppDatabaseOpener` opens on first use, so
/// a cold start that lands on Paper Home does not pay for schema creation, and
/// a launch that goes straight to the reader does not pay for the home screen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final SharedPreferences preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const PaperApp(),
    ),
  );
}
