/// Build-time constants for PaperOS.
///
/// Anything here is a deliberate product decision that more than one layer
/// needs to agree on.
library;

abstract final class PaperConfig {
  /// Reverse-DNS application id. Also the Android `namespace`.
  static const String appId = 'dev.paperos.app';

  /// Shown in the Android launcher and in Settings.
  static const String appName = 'PaperOS';

  /// Database file name inside the app databases directory.
  static const String databaseName = 'paperos.db';

  /// Schema version. Bump together with a migration in `AppDatabase`.
  static const int databaseVersion = 1;

  /// Sub-directory of app documents storage that holds imported originals.
  static const String libraryDirectoryName = 'library';

  /// Files above this size are refused on import rather than silently filling
  /// the device. Chosen because no mainstream reader handles larger files
  /// gracefully on a phone.
  static const int maxImportBytes = 512 * 1024 * 1024;

  /// Text documents larger than this are not fully paginated up front; the
  /// reader falls back to chunked loading.
  static const int maxTextReaderBytes = 16 * 1024 * 1024;

  /// How often the reader coalesces progress writes while reading.
  static const Duration progressWriteDebounce = Duration(milliseconds: 500);

  /// How long the reader waits before saving progress after the user stops
  /// interacting.
  static const Duration readerIdleSaveDelay = Duration(milliseconds: 700);

  /// Delay before the reader control bar hides itself.
  static const Duration readerChromeAutoHide = Duration(seconds: 4);

  /// Number of recently opened documents surfaced on Paper Home.
  static const int homeRecentLimit = 6;

  /// Maximum rows in the app drawer before the list virtualises beyond this.
  static const int appDrawerPageSize = 400;
}
