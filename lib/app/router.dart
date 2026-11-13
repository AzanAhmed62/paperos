import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/display/display_policy.dart';
import '../features/files/application/files_providers.dart';
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
import 'paper_back_policy.dart';
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

/// The PaperOS router.
///
/// The five top-level destinations live in a [StatefulShellRoute] with an
/// indexed stack, so moving between them preserves each one's scroll position
/// and back stack. The reader, the note editor, the app drawer, tasks and
/// search are pushed above the shell on the root navigator.
///
/// The router is provided rather than global so that a test, a hot restart and
/// an activity recreation each start from an explicit configuration instead of
/// inheriting route state from a previous tree.
final appRouterProvider = Provider<GoRouter>((Ref ref) {
  final GoRouter router = createAppRouter();
  ref.onDispose(router.dispose);
  return router;
});

GoRouter createAppRouter() {
  // One navigator key per router. A global key would make two live routers in
  // one process (for example, a widget test that pumps a second app) collide.
  final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.home,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell shell,
            ) {
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
            context,
            state,
            NoteEditorScreen(noteId: state.pathParameters['noteId']!),
          );
        },
      ),
      GoRoute(
        path: Routes.apps,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadePage(context, state, const AppsScreen());
        },
      ),
      GoRoute(
        path: Routes.tasks,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadePage(context, state, const TasksScreen());
        },
      ),
      GoRoute(
        path: Routes.search,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadePage(context, state, const SearchScreen());
        },
      ),
      GoRoute(
        path: Routes.reader,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadePage(
            context,
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
}

/// The frame every destination screen is drawn inside.
///
/// This is also the one place where Android Back is interpreted for the whole
/// hierarchy. Keeping the decision here rather than in five branch screens is
/// what makes the contract deterministic: the shell is the root route, so it is
/// the only widget guaranteed to see a back gesture when no overlay is open.
class PaperShell extends ConsumerWidget {
  const PaperShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool filesFolderOpen =
        shell.currentIndex == PaperDestination.files.index &&
        ref.watch(filesBrowseProvider).isNotEmpty;

    return PopScope(
      // Paper Home is a terminal surface. Back on it is consumed rather than
      // popping the root route and finishing the activity, which would reveal
      // another launcher on a device where PaperOS owns HOME.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        final GoRouter router = ref.read(appRouterProvider);
        final PaperBackAction action = decidePaperBack(
          overlayCanPop: router.canPop(),
          filesFolderOpen: filesFolderOpen,
          onHomeBranch: shell.currentIndex == PaperDestination.home.index,
        );
        switch (action) {
          case PaperBackAction.popOverlay:
            router.pop();
          case PaperBackAction.popFilesFolder:
            ref.read(filesBrowseProvider.notifier).pop();
          case PaperBackAction.goHome:
            shell.goBranch(PaperDestination.home.index, initialLocation: true);
          case PaperBackAction.consume:
            // Deliberately do nothing: the gesture belongs to Paper Home.
            break;
        }
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: PaperDestinationBar(
          currentIndex: shell.currentIndex,
          onSelect: (int index) {
            if (index == shell.currentIndex) return;
            // goBranch preserves every branch's navigator and scroll state.
            // context.go would rebuild the branch route instead.
            shell.goBranch(index);
          },
        ),
      ),
    );
  }
}

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
CustomTransitionPage<void> _fadePage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  // The display policy owns the timing. E-Ink resolves to zero, which removes
  // the overlay cross-fade instead of merely shortening it.
  final Duration duration = DisplayPolicyScope.of(context).navigationDuration;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
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
