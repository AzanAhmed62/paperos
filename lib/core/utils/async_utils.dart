import 'dart:async';

import 'package:paperos/core/errors/paper_exception.dart';

/// Runs [action] and converts any error into a [PaperException].
///
/// Repositories throw `PaperException`s deliberately. Anything else escaping a
/// repository is a bug or a platform surprise; wrapping it here means no screen
/// ever has to guess whether it received a `FileSystemException`,
/// a `DatabaseException`, or an `ArgumentError`.
Future<T> guard<T>(
  PaperException Function(Object error, StackTrace stackTrace) map,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } on PaperException {
    rethrow;
  } catch (error, stackTrace) {
    throw map(error, stackTrace);
  }
}

/// A tiny, allocation-free debouncer used for progress writes and search input.
///
/// Progress is written while scrolling a text document; without coalescing,
/// opening a long text file would produce thousands of SQLite writes.
class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 400)});

  final Duration delay;
  Timer? _timer;
  void Function()? _pending;

  void run(void Function() action) {
    _pending = action;
    _timer?.cancel();
    _timer = Timer(delay, () {
      final action = _pending;
      _pending = null;
      action?.call();
    });
  }

  /// Runs the pending action immediately, if any.
  void flush() {
    _timer?.cancel();
    _timer = null;
    final action = _pending;
    _pending = null;
    action?.call();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  bool get isPending => _pending != null;

  void dispose() => cancel();
}
