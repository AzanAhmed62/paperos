import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../features/library/domain/document.dart';
import '../errors/paper_exception.dart';

/// A file the user chose, before PaperOS has copied it anywhere.
class PickedFile {
  const PickedFile({
    required this.path,
    required this.name,
    required this.byteSize,
    this.sourceUri,
  });

  /// A readable path for the picked file. On Android this is a cache copy that
  /// is guaranteed to exist for the duration of the picker session.
  final String path;

  /// Original display name, including extension.
  final String name;

  final int byteSize;

  /// The original location, when the platform reports one. Recorded so that
  /// re-importing the same file is a no-op instead of a duplicate.
  final String? sourceUri;

  DocumentFormat get format => DocumentFormat.fromFileName(name);
}

/// A folder the user granted PaperOS access to.
class PickedFolder {
  const PickedFolder({required this.path, required this.name});

  final String path;
  final String name;
}

/// Obtains documents and folders from the user through the system picker.
///
/// On Android this is the Storage Access Framework, which is why PaperOS
/// declares no storage permissions: the user grants access to the specific
/// things they pick, and revoking that grant cannot break the library, because
/// imports are copied into app-private storage.
abstract interface class DocumentImportService {
  /// Shows the system document picker. Returns null when the user cancels.
  Future<PickedFile?> pickDocument({List<String>? extensions});

  /// Shows the system folder picker. Returns null when the user cancels or the
  /// platform does not support folder picking.
  Future<PickedFolder?> pickFolder();
}

class SystemDocumentImportService implements DocumentImportService {
  const SystemDocumentImportService();

  @override
  Future<PickedFile?> pickDocument({List<String>? extensions}) async {
    List<String> allowed = extensions ?? DocumentFormat.importableExtensions;
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: allowed,
        // PaperOS copies the file itself, straight from the path, so the bytes
        // never need to sit in memory.
        withData: false,
        withReadStream: false,
        lockParentWindow: true,
      );
      if (result == null || result.files.isEmpty) return null;

      final PlatformFile file = result.files.first;
      final String? path = file.path;
      if (path == null || path.isEmpty) {
        // Some document providers return a stream instead of a path. PaperOS
        // refuses rather than buffering an unbounded file into memory.
        throw PaperException.permission(
          'That file cannot be opened directly. '
          'Save it to your Downloads folder first, then import it again.',
        );
      }
      final String? identifier = file.identifier;
      return PickedFile(
        path: path,
        name: file.name.trim().isNotEmpty ? file.name : p.basename(path),
        byteSize: file.size,
        sourceUri: identifier != null && identifier.isNotEmpty
            ? identifier
            : (path.startsWith('content://') ? path : null),
      );
    } on PaperException {
      rethrow;
    } catch (error) {
      throw PaperException.permission(
        'PaperOS could not open the system file picker.',
        cause: error,
      );
    }
  }

  @override
  Future<PickedFolder?> pickFolder() async {
    try {
      final String? path = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose a folder',
        lockParentWindow: true,
      );
      if (path == null || path.isEmpty) return null;
      return PickedFolder(path: path, name: p.basename(path));
    } catch (_) {
      // Folder picking is unavailable or refused on this platform. Callers
      // treat null as "not supported" and hide the affordance.
      return null;
    }
  }
}

/// Reads a file's size without loading it, for pre-flight checks.
Future<int> sizeOfFile(String path) async {
  final File file = File(path);
  if (!file.existsSync()) {
    throw PaperException.missingFile('The file for this document is gone.');
  }
  return file.length();
}
