import 'package:quark/utils/file_kind.dart';

/// The extensions the read-only document viewer opens: Word documents, with
/// or without macros, OpenDocument text and Rich Text Format.
const documentViewerExtensions = {'.docx', '.docm', '.odt', '.rtf'};

/// Whether the file called [name] opens in the read-only document viewer
/// (#3265).
bool opensInDocumentViewer(String name) =>
    documentViewerExtensions.contains(fileExtension(name));

/// The path of the `.qdoc` that "Open as Quark doc" writes beside the
/// document at [path]: the same folder and name, with the extension swapped.
String siblingQdocPath(String path) {
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  return '${dot > slash + 1 ? path.substring(0, dot) : path}.qdoc';
}
