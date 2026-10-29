import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/paper_home_screen.dart';
import '../features/launcher/presentation/apps_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/files/presentation/files_screen.dart';
import '../features/notes/presentation/note_editor_screen.dart';
import '../features/notes/presentation/notes_screen.dart';
import '../features/reader/presentation/reader_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/tasks/presentation/tasks_screen.dart';
import '../shared/widgets/paper_widgets.dart';
import '../theme/paper_space.dart';
import '../theme/paper_typography.dart';
import 'paper_destinations.dart';

/// Route paths, defined once so that in-app navigation and OS deep links cannot
/// disagree about a path.
abstract final class Routes {
  static const String home = '/';
  static const String library = '/library';
  static const String files = '/files';
  static const String notes = '/notes';
  static const String noteEditor = '/notes/:noteId';
  static const String tasks = '/tasks';
  static const String settings = '/settings';
  static const String apps = '/apps';
  static const String search = '/search';
  static const String reader = '/read/:documentId';

  /// Path of the reader for [documentId].
  ///
  /// Built here rather than by string interpolation at call sites so that a
  /// change to the route shape is a one-line change.
  static String readerPath(String documentId) => '/read/$documentId';

  /// Path of the note editor for [noteId].
  static String noteEditorPath(String noteId) => '/notes/$noteId';
}

/// The navigator that sits above the destination shell, so the reader and the
/// editors cover the shell instead of being laid out beside it.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// The PaperOS router.
///
/// The five top-level destinations live in a [StatefulShellRoute] with an
/// indexed stack, so moving between them preserves each one's scroll position
/// and back stack — the behaviour a document-centric app needs, where "back"
/// must return to the list the user came from rather than to the start of the
/// app. The reader, the note editor, the app drawer and search are pushed above
/// the shell.
final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: Routes.home,
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (BuildContext context, GoRouterState state, Widget shell) {
        return PaperShell(shell: shell);
      },
      branches: <StatefulShellBranch>[
        _tab(Routes.home, const PaperHomeScreen()),
        _tab(Routes.library, const LibraryScreen()),
        _tab(Routes.files, const FilesScreen()),
        _tab(Routes.notes, const NotesScreen()),
        _tab(Routes.settings, const SettingsScreen()),
      ],
    ),
    GoRoute(
      path: Routes.noteEditor,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (BuildContext context, GoRouterState state) {
        return _fadePage(
          state,
          NoteEditorScreen(noteId: state.pathParameters['noteId']!),
        );
      },
    ),
    GoRoute(
      path: Routes.apps,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (BuildContext context, GoRouterState state) {
        return _fadePage(state, const AppsScreen());
      },
    ),
    GoRoute(
      path: Routes.tasks,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (BuildContext context, GoRouterState state) {
        return _fadePage(state, const TasksScreen());
      },
    ),
    GoRoute(
      path: Routes.search,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (BuildContext context, GoRouterState state) {
        return _fadePage(state, const SearchScreen());
      },
    ),
    GoRoute(
      path: Routes.reader,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (BuildContext context, GoRouterState state) {
        return _fadePage(
          state,
          ReaderScreen(documentId: state.pathParameters['documentId']!),
        );
      },
    ),
  ],
  errorBuilder: (BuildContext context, GoRouterState state) {
    return PaperRouteErrorScreen(location: state.uri.toString());
  },
);

StatefulShellBranch _tab(String path, Widget child) =>
    StatefulShellBranch(routes: <RouteBase>[_tabRoute(path, child)]);

GoRoute _tabRoute(String path, Widget child) {
  return GoRoute(
    path: path,
    pageBuilder: (BuildContext context, GoRouterState state) {
      // Destination switches are instant: the shell shows a different stack,
      // and cross-fading it would only make the app feel slower.
      return NoTransitionPage<void>(child: child);
    },
  );
}

/// Overlays open with a short cross-fade and no horizontal slide: they sit on
/// the same physical "page" rather than a step sideways.
CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 140),
    transitionsBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
            return child;
          }
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
  );
}

/// Shown when the OS hands PaperOS a path it does not know — for example a
/// `VIEW` intent for a file type the reader does not support yet.
class PaperRouteErrorScreen extends StatelessWidget {
  const PaperRouteErrorScreen({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(PaperSpace.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'PaperOS cannot open this yet',
                style: PaperTypography.of(context).heading,
              ),
              const SizedBox(height: PaperSpace.sm),
              Text(location, style: PaperTypography.of(context).bodyQuiet),
              const SizedBox(height: PaperSpace.lg),
              PaperButton(
                label: 'Go to Paper Home',
                onPressed: () => context.go(Routes.home),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
