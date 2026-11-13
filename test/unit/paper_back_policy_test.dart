import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/paper_back_policy.dart';

/// Android Back is a single gesture with four possible meanings in PaperOS.
/// The decision is pure so it can be proved here rather than inferred from a
/// device recording.
void main() {
  test('an overlay is closed before anything else', () {
    expect(
      decidePaperBack(
        overlayCanPop: true,
        filesFolderOpen: true,
        onHomeBranch: false,
      ),
      PaperBackAction.popOverlay,
    );
  });

  test('a Files folder steps out before the branch changes', () {
    expect(
      decidePaperBack(
        overlayCanPop: false,
        filesFolderOpen: true,
        onHomeBranch: false,
      ),
      PaperBackAction.popFilesFolder,
    );
  });

  test('another primary surface returns to Paper Home', () {
    expect(
      decidePaperBack(
        overlayCanPop: false,
        filesFolderOpen: false,
        onHomeBranch: false,
      ),
      PaperBackAction.goHome,
    );
  });

  test('Back on Paper Home is consumed, not forwarded to Android', () {
    expect(
      decidePaperBack(
        overlayCanPop: false,
        filesFolderOpen: false,
        onHomeBranch: true,
      ),
      PaperBackAction.consume,
    );
  });
}
