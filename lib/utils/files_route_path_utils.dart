import 'package:flutter/foundation.dart';

String filesRouteDisplayPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed == '/') {
    return '/files';
  }
  return trimmed.startsWith('/files') ? trimmed : '/files$trimmed';
}

bool isLikelyFilePath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed.endsWith('/')) {
    return false;
  }

  final normalized = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
  final segments = normalized.split('/');
  if (segments.isEmpty) {
    return false;
  }

  final lastSegment = segments.last;
  final dotIndex = lastSegment.lastIndexOf('.');
  return dotIndex > 0 && dotIndex < lastSegment.length - 1;
}

bool hasSupportedFilesEditorForPath(String path) {
  final normalized = path.trim().toLowerCase();
  return normalized.endsWith('.qdoc') || normalized.endsWith('.qsheet');
}

bool hasSupportedFilesEditorForType(String fileType) {
  final normalized = fileType.trim().toLowerCase();
  return normalized == 'qdoc' || normalized == 'qsheet';
}

/// Backend file types with no in-app viewer yet.
///
/// These open in `GenericFileViewerPage` — download plus "Open with…" — rather
/// than falling through to the "No supported editor" dead end. Named document
/// types are included deliberately: without them a `.pdf` ends up worse off
/// than an unclassified file, which reaches that page as `generic` (#1184).
///
/// `xlsx` is here for the same reason, and only as a fallback: the file
/// browser offers to convert a workbook to a `.qsheet` before reaching this,
/// so a raw workbook lands here when it is opened by URL rather than tapped
/// (#1741). Sheets reads `.qsheet`, never `.xlsx` itself.
bool usesGenericFileViewer(String fileType) {
  const noInAppViewer = {'generic', 'pdf', 'docx', 'slideshow', 'epub', 'xlsx'};
  final normalized = fileType.trim().toLowerCase();
  return normalized.isEmpty || noInAppViewer.contains(normalized);
}

/// Whether the generic viewer should hand [fileType] to the system on arrival.
///
/// iOS previews a PDF in QuickLook with no app picker, so the "Open with…" tap
/// only delays what would happen anyway (#1807). Android can offer several PDF
/// apps, so the tap stays a real choice there; web has no system open at all.
bool opensStraightInSystemViewer(
  String fileType, {
  required bool isWeb,
  required TargetPlatform platform,
}) =>
    !isWeb &&
    platform == TargetPlatform.iOS &&
    fileType.trim().toLowerCase() == 'pdf';

/// The last path segment with [extension] removed, when it carries it.
///
/// Both editors derive the name they save back under this way. They each used
/// to count the extension by hand — `.qsheet` as 8 characters and `.qdoc` as 6,
/// one too many each — so every save cut a letter off the name and wrote to a
/// new file: `budget.qsheet` was saved as `budge.qsheet`.
String fileNameWithoutExtension(String path, String extension) {
  final name = path.split('/').last;
  return name.endsWith(extension)
      ? name.substring(0, name.length - extension.length)
      : name;
}
