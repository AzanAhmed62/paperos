# Navigation architecture

This document defines the navigation contract PaperOS follows as an Android
launcher. It is deliberately stricter than "the back button goes back": a
launcher must always know which surface owns Back, must never accidentally expose
another launcher, and must distinguish "the user pressed Home" from "the user
opened a PDF from another app".

The implementation is split across four small pieces:

| Piece | File | Responsibility |
| --- | --- | --- |
| Route table and shell | `lib/app/router.dart` | Owns the five branches, root overlays, and the single Back handler. |
| Pure Back policy | `lib/app/paper_back_policy.dart` | Decides what Back means without a widget, router, or platform. |
| Files browse stack | `lib/features/files/application/files_providers.dart` | Keeps the folder depth where the shell can inspect and pop it. |
| Intent classifier | `android/.../SystemIntentChannel.kt`, `lib/app/system_intent_controller.dart` | Distinguishes HOME/LAUNCHER from `ACTION_VIEW` and resets the hierarchy. |

## Hierarchy levels

PaperOS uses four levels. A level is a navigation contract, not a visual style.

| Level | Surfaces | Route / owner | Back result |
| --- | --- | --- | --- |
| **0 — Home** | Paper Home | `/` in the Home branch | Consumed. The activity does not finish and no other launcher is revealed. |
| **1 — Primary surfaces** | Library, Files (granted-folder list), Notes, Settings | Branch roots `/library`, `/files`, `/notes`, `/settings` | Return to Paper Home. Branch state is preserved. |
| **2 — Child surfaces** | Reader, note editor, app drawer, Tasks, Search, Files folder views | Root-navigator overlays; Files depth lives in `filesBrowseProvider` | Close the overlay, or step out one Files folder. The owner is revealed. |
| **3 — Android/system surfaces** | SAF picker, HOME-role dialog, Android home-app settings, share/Open-with, system Recents/status bar | Android, outside Flutter | Android returns to PaperOS; PaperOS does not try to "back" through system UI. |

The five Level 1 destinations are fixed:

```
Home · Library · Files · Notes · Settings
```

There is no sixth bottom destination. Tasks, Search, the app drawer and the
reader are Level 2 because they are opened from a surface and must return to it.

## Route map

```
/                         Paper Home                    Level 0
/library                  Library                       Level 1
/files                    Files: granted folders        Level 1
/notes                    Notes                         Level 1
/settings                 Settings                      Level 1

/read/:documentId         Reader overlay                Level 2
/notes/:noteId            Note editor overlay           Level 2
/apps                     App drawer overlay            Level 2
/tasks                    Tasks overlay                 Level 2
/search                   Search overlay                Level 2
```

The five Level 1 destinations live in one
`StatefulShellRoute.indexedStack`. Each branch owns a navigator and keeps its
scroll position and local state when another branch is selected. Level 2 routes
are declared above the shell with `parentNavigatorKey: rootNavigatorKey`, so they
cover the destination bar instead of appearing inside a branch.

Unknown locations are rendered by `PaperRouteErrorScreen`, which offers a single
action back to Paper Home. A route error is not a dead end.

## Back contract

The shell owns exactly one `PopScope`:

```dart
PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, result) {
    if (didPop) return;
    // decidePaperBack(...)
  },
  child: ...,
)
```

`canPop: false` is intentional. PaperOS is a launcher: letting the root route pop
would finish `MainActivity`, and on a device where PaperOS owns HOME that can
expose another launcher or the system wallpaper. Back on Paper Home is a consumed
gesture, not an exit.

The decision itself is a pure function:

```dart
PaperBackAction decidePaperBack({
  required bool overlayCanPop,
  required bool filesFolderOpen,
  required bool onHomeBranch,
}) {
  if (overlayCanPop) return PaperBackAction.popOverlay;
  if (filesFolderOpen) return PaperBackAction.popFilesFolder;
  if (!onHomeBranch) return PaperBackAction.goHome;
  return PaperBackAction.consume;
}
```

The resulting order is fixed:

1. **Overlay first.** If a Level 2 root route can pop, pop it. Reader, note
   editor, app drawer, Tasks and Search close and reveal the surface that opened
   them. The overlay's own route handles the gesture; the shell policy is the
   fallback for a primary surface.
2. **Files folder next.** If Files is inside a granted location, pop one step.
   The location root is itself a step, so Back from a location root returns to
   the granted-folder list, and Back from a subfolder returns to its parent.
3. **Primary surface next.** If the visible branch is not Home, switch to the
   Home branch. `StatefulNavigationShell.goBranch(home, initialLocation: true)`
   resets Home to its root without discarding the other branches.
4. **Home last.** Consume the gesture. Nothing is pushed, popped, finished, or
   delegated to another launcher.

Consequences worth stating explicitly:

- Back from Library, Files, Notes or Settings goes to Home, never to the
  previously selected tab. PaperOS has no hidden tab history.
- Tapping the already-selected destination does nothing. It does not scroll to
  the top or reset the branch; that avoids surprising a reader who tapped the
  tab by accident.
- Back inside a Files subfolder steps one level at a time. It does not jump
  straight to Home.
- Back on Home is consumed even when PaperOS does **not** currently hold the
  Android HOME role. The role changes how Android starts the activity, not the
  in-app Back contract.
- When a text field is focused, Android delivers the first Back to the input
  method, not to Flutter. The overlay closes on the next Back. This is platform
  behaviour: the IME is a Level 3 system surface and owns its own dismissal.

### Predictive Back

The manifest keeps `android:enableOnBackInvokedCallback="true"`, and the app uses
`PopScope`/`onPopInvokedWithResult` rather than the obsolete `WillPopScope`. A
Back that is consumed on Home therefore does not animate a predictive exit. On
Android versions that support predictive Back, an overlay that is going to close
can still show the system preview; the final decision remains the policy above.

## Files folder state

Files used to keep its folder stack in a `StatefulWidget`. That made the shell
unable to answer "is Files inside a folder?" without reaching into a descendant's
private state. The stack now lives in `filesBrowseProvider`:

```dart
class FilesBrowseStep {
  final BrowsedLocation location;
  final String? directoryUri; // null = location root
  final String label;
}
```

- `openLocation` starts at one step (the location root).
- `push` adds a subfolder.
- `pop` removes one step and returns `false` when already empty.
- `reset` clears the stack for a HOME/LAUNCHER intent.

The shell reads only `filesBrowseProvider.isNotEmpty` and the current branch. It
never needs to know which screen is mounted.

## Router lifetime and recovery

The router is a Riverpod provider, not a global:

```dart
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = createAppRouter();
  ref.onDispose(router.dispose);
  return router;
});
```

`createAppRouter()` creates a fresh `GlobalKey<NavigatorState>` for each router.
This matters for two reasons:

- a hot restart or an activity recreation must not inherit route state from a
  previous tree;
- two live routers in one process (for example, two widget tests, or a future
  multi-window surface) must not collide on one global navigator key.

A cold start always begins at `/`. PaperOS deliberately does not persist the
last route across process death: a launcher should come back to Home, not to a
reader page that no longer has a live document session. The Android
`stateNotNeeded="true"` flag matches that contract.

## Android launcher integration

### Manifest contract

`MainActivity` is the only activity. It is exported because it must be
launchable, selectable as HOME, and able to receive documents. Its launcher
attributes are:

| Attribute | Value | Why |
| --- | --- | --- |
| `launchMode` | `singleTask` | One PaperOS task; a second launch is delivered to the existing activity through `onNewIntent` instead of stacking duplicates. |
| `taskAffinity` | `dev.paperos.app` | Gives the launcher task a real identity instead of joining the caller's task. |
| `stateNotNeeded` | `true` | Android may destroy and recreate the activity; PaperOS starts deterministically at Home. |
| `clearTaskOnLaunch` | `false` | Pressing Home must not clear the task every time. |
| `excludeFromRecents` | `false` | The launcher remains visible in Android Recents like a normal app. |
| `enableOnBackInvokedCallback` | `true` | Opts into modern Back dispatch. |

Three intent filters are declared:

1. `MAIN` + `LAUNCHER` — ordinary app launch.
2. `MAIN` + `HOME` + `DEFAULT` — HOME-role candidacy.
3. `VIEW` for `content://` and `file://` `application/pdf` and `text/plain` —
   "Open with PaperOS".

The `<queries>` block declares launcher activities, HOME activities, PDF viewers
and `PROCESS_TEXT`. These are package-visibility declarations, not permissions.

### Why intents are classified

A launcher can be brought forward for very different reasons:

- the user pressed Home;
- the user tapped the PaperOS icon;
- another app sent a PDF or text file;
- Android recreated the activity after process death.

If every one of those resumed the last visible screen, pressing Home while
reading would show the reader again. `SystemIntentChannel` answers one question —
"why did Android bring us here?" — and returns exactly one of:

| Intent | Classification | Dart result |
| --- | --- | --- |
| `ACTION_MAIN` + `CATEGORY_HOME` | `home` | Reset the hierarchy to Paper Home. |
| `ACTION_MAIN` + `CATEGORY_LAUNCHER` | `launcher` | Reset the hierarchy to Paper Home. |
| `ACTION_VIEW` | `view` | Leave the document to `FileBrowserChannel`; import and open it. |
| Anything else | ignored | No navigation change. |

`FileBrowserChannel` still owns `ACTION_VIEW` because a VIEW intent carries the
one-shot content grant. `SystemIntentChannel` never reads or stores that URI.

### Cold start, warm start, and recovery

- **Cold start from HOME or LAUNCHER.** `MainActivity.configureFlutterEngine`
  passes the activity's own `intent` to `SystemIntentChannel.setInitialIntent`.
  Dart calls `ready`, receives the stashed kind, and resets to Home. The app is
  already at Home on a cold start, so the reset is idempotent.
- **Warm HOME/LAUNCHER.** Android delivers `onNewIntent`. `MainActivity` forwards
  it to both channels. If Dart is listening, the kind is emitted immediately;
  otherwise it is stashed for `takePending`.
- **Cold or warm VIEW.** `FileBrowserChannel` keeps its existing initial-intent
  and pending-intent path. `SystemIntentController` asks
  `ExternalOpenController` to drain it. It never resets to Home first, which
  would race the reader navigation.
- **Resume.** `PaperApp.didChangeAppLifecycleState(resumed)` drains pending
  intents again and refreshes the HOME-role status. Native `takePending` clears
  the value, so a resume does not replay an old intent.
- **Process death.** `stateNotNeeded=true` plus a fresh router means the app
  returns to Paper Home. There is no stale route stack to restore.
- **Duplicate tasks.** `singleTask` should route a second launch into the
  existing task. The app does not create a second `MainActivity` itself. This is
  the intended contract; it still needs a real-device duplicate-task check
  because Android OEMs vary.

## Testing

The navigation contract is covered at three levels:

| Test | What it proves |
| --- | --- |
| `test/unit/paper_back_policy_test.dart` | Every branch of the pure policy, including Home consuming Back. |
| `test/unit/router_recovery_test.dart` | Two routers can coexist; each starts at Home; disposal is safe. |
| `test/widget/back_navigation_test.dart` | Real `PaperApp`: primary surface → Home, Home consumed, overlay closes first, Files folder steps then Home. |
| `test/widget/app_shell_test.dart` | The five destinations boot and branch state survives switching. |
| `test/unit/system_intent_test.dart` | HOME/LAUNCHER reset, VIEW drains the document, cold/warm delivery, duplicate delivery. |
| `test/widget/home_launcher_test.dart` | Home quick actions, pinned apps, role status, date and density preferences. |
| `test/widget/apps_screen_test.dart` | Drawer recents/favourites, launch, pin/unpin, refresh, restricted and empty states, icon preference. |

The widget tests simulate Android Back with
`WidgetsBinding.instance.handlePopRoute()`, which is the same entry point the
engine uses for the system Back gesture.

## Boundaries and unverified behaviour

- Automated tests prove the Flutter hierarchy and the intent controller logic.
  They do not prove that a specific OEM delivers `onNewIntent` exactly as
  expected, that the HOME-role dialog appears, or that duplicate tasks behave
  identically across launchers.
- The HOME-role selection itself is a system dialog. It cannot be accepted by an
  automated widget test.
- Android's predictive-Back preview is a system animation. The code opts in and
  uses the modern API, but the visual preview is not device-verified here.
- Back from a Level 3 system surface is owned by Android. PaperOS does not
  attempt to intercept SAF pickers, the role dialog, or system settings.

The manual checks for these paths are in [`manual-testing.md`](manual-testing.md).
