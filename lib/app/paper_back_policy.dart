/// What Android Back should do at the current PaperOS surface.
///
/// The policy is deliberately a pure function: the router, the shell and the
/// Android activity are all involved in delivering a back gesture, and the one
/// decision that must never regress is testable without any of them.
enum PaperBackAction {
  /// A root-navigator overlay (reader, editor, search, drawer, tasks) is on
  /// top. Close it and reveal the surface that opened it.
  popOverlay,

  /// Files is browsing a granted folder. Step back to the folder list.
  popFilesFolder,

  /// A primary surface is showing. Return to Paper Home.
  goHome,

  /// Paper Home is already the root. Consume the gesture.
  consume,
}

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
