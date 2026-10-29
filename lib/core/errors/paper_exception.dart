/// Every failure PaperOS can surface to a user has exactly one of these kinds.
///
/// A single exception type with a discriminator (instead of a deep class
/// hierarchy) keeps error handling in the UI predictable: a screen renders the
/// [message] and, when the kind says it is worth retrying, offers a retry.
library;

enum PaperErrorKind {
  /// A database read/write failed.
  storage,

  /// The file backing a library entry is gone or unreadable.
  missingFile,

  /// The format is recognised but PaperOS cannot open it yet.
  unsupportedFormat,

  /// The file exists but its contents are not valid for the format.
  corruptDocument,

  /// Android refused, most often because the SAF grant or permission is gone.
  permission,

  /// A platform channel call failed or is not implemented on this OS.
  platform,

  /// The user cancelled a picker. Never shown as an error.
  cancelled,

  /// Anything genuinely unexpected.
  unknown,
}

class PaperException implements Exception {
  const PaperException(this.kind, this.message, {this.cause, this.detail});

  const PaperException.storage(this.message, {this.cause, this.detail})
    : kind = PaperErrorKind.storage;

  const PaperException.missingFile(this.message, {this.cause, this.detail})
    : kind = PaperErrorKind.missingFile;

  const PaperException.unsupportedFormat(
    this.message, {
    this.cause,
    this.detail,
  }) : kind = PaperErrorKind.unsupportedFormat;

  const PaperException.corruptDocument(this.message, {this.cause, this.detail})
    : kind = PaperErrorKind.corruptDocument;

  const PaperException.permission(this.message, {this.cause, this.detail})
    : kind = PaperErrorKind.permission;

  const PaperException.platform(this.message, {this.cause, this.detail})
    : kind = PaperErrorKind.platform;

  const PaperException.unknown(this.message, {this.cause, this.detail})
    : kind = PaperErrorKind.unknown;

  final PaperErrorKind kind;

  /// User-facing sentence. Must already be phrased for a human.
  final String message;

  /// Underlying error, kept for logging only. Never shown.
  final Object? cause;

  /// Extra developer-facing context.
  final String? detail;

  /// Whether showing a "Try again" affordance makes sense.
  bool get isRetryable =>
      kind == PaperErrorKind.storage ||
      kind == PaperErrorKind.platform ||
      kind == PaperErrorKind.permission ||
      kind == PaperErrorKind.unknown;

  /// Whether the problem is the file itself rather than a transient condition.
  bool get isPermanent =>
      kind == PaperErrorKind.missingFile ||
      kind == PaperErrorKind.unsupportedFormat ||
      kind == PaperErrorKind.corruptDocument;

  @override
  String toString() =>
      'PaperException(${kind.name}): $message'
      '${detail == null ? '' : ' | $detail'}'
      '${cause == null ? '' : ' | caused by $cause'}';
}
