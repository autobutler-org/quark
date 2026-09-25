import 'package:desktop_drop/desktop_drop.dart';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quark/services/upload_chunk_source.dart';
import 'package:quark/utils/file_browser_path_utils.dart';

/// How deep we walk into a dropped or picked folder before giving up.
///
/// Nothing in a browser drop is cyclic today, but the tree is attacker-shaped
/// input and walking it is recursive, so it gets a ceiling.
const int kMaxUploadDepth = 16;

/// How many files a single folder upload will take.
///
/// Uploads run one file at a time, so this is not a memory ceiling — it is a
/// guard against a stray drop of a home directory turning into tens of
/// thousands of requests with no way to stop it.
const int kMaxUploadFiles = 2000;

/// A file waiting to be uploaded, and where it belongs relative to the upload
/// root.
///
/// [build] is deferred on purpose: a folder upload of any size cannot hold
/// every file's bytes at once, so the caller builds each multipart file
/// immediately before sending it and lets it go afterwards.
///
/// [openChunkSource] is the large-file route added by #1629. Deferring it too
/// serves a second purpose: opening the file is how its size becomes known,
/// and the size is what decides between a session and today's single multipart
/// POST.
class PendingUpload {
  const PendingUpload({
    required this.relativeDir,
    required this.name,
    required this.build,
    this.openChunkSource,
    this.renderThumbnail,
  });

  /// Directory relative to the upload root, `''` for the root itself.
  /// Always already sanitized — see [sanitizeRelativeDir].
  final String relativeDir;

  /// File name, for progress and error messages.
  final String name;

  final Future<http.MultipartFile?> Function() build;

  /// Opens this file for ranged reads, or null when the platform can only hand
  /// over the whole thing at once.
  ///
  /// Null on a [PendingUpload] built the old way, which is what keeps every
  /// existing caller working: a file with no chunk source simply takes the
  /// single-request path however large it is.
  final Future<UploadChunkSource?> Function()? openChunkSource;

  /// Renders the thumbnail this file uploads with (#2379), a JPEG, or null
  /// where the platform renders none. Called once per file, when it is about
  /// to be sent.
  final Future<Uint8List?> Function()? renderThumbnail;
}

/// The outcome of walking a dropped folder.
class DropFlattenResult {
  const DropFlattenResult({
    required this.uploads,
    required this.truncated,
    required this.skippedTooDeep,
  });

  final List<PendingUpload> uploads;

  /// True when [kMaxUploadFiles] was reached and the walk stopped early.
  final bool truncated;

  /// Number of directories left unread because they sat deeper than
  /// [kMaxUploadDepth].
  final int skippedTooDeep;
}

/// Normalizes a relative directory, or returns null if it tries to escape.
///
/// The upload endpoint deliberately drops any directory in a multipart
/// filename (`path.Join(rootDir, filepath.Base(fileName))`) as traversal
/// protection, so structure has to travel through `rootDir` instead. That
/// makes `rootDir` the thing an attacker would aim at, and it is derived from
/// names the browser handed us — so it gets validated here, once, for every
/// caller.
///
/// Returns `''` for the upload root itself. Returns null when any segment is
/// `..`, which is the case a caller must refuse rather than clean up.
String? sanitizeRelativeDir(String raw) {
  final segments = raw.replaceAll(r'\', '/').split('/');
  final kept = <String>[];
  for (final segment in segments) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty || trimmed == '.') {
      continue;
    }
    if (trimmed == '..') {
      return null;
    }
    kept.add(trimmed);
  }
  return kept.join('/');
}

/// The directory part of a path relative to the upload root.
///
/// `photos/2024/a.jpg` → `photos/2024`, and a bare `a.jpg` → `''`.
String relativeDirOf(String relativePath) {
  final normalized = relativePath.replaceAll(r'\', '/');
  final lastSlash = normalized.lastIndexOf('/');
  if (lastSlash < 0) {
    return '';
  }
  return normalized.substring(0, lastSlash);
}

/// Where [relativeDir] lands under [uploadPath].
String uploadTargetPath(String uploadPath, String relativeDir) {
  if (relativeDir.isEmpty) {
    return uploadPath;
  }
  return joinPath(uploadPath, relativeDir);
}

/// Groups uploads by their target directory, preserving encounter order.
///
/// One group is one nested upload request, so a folder of 500 files spread
/// over 10 directories is 10 destinations rather than 500 guesses.
Map<String, List<PendingUpload>> groupByRelativeDir(
  List<PendingUpload> uploads,
) {
  final grouped = <String, List<PendingUpload>>{};
  for (final upload in uploads) {
    (grouped[upload.relativeDir] ??= <PendingUpload>[]).add(upload);
  }
  return grouped;
}

/// Flattens dropped items to their leaf files, keeping each file's directory.
///
/// A dropped folder arrives as [DropItemDirectory], which is a sibling of
/// [DropItemFile] rather than a subtype — both extend [DropItem]. Filtering on
/// `is! DropItemFile` therefore discards the whole folder even though its
/// contents are sitting in `.children` (#1614).
DropFlattenResult flattenDroppedItems(
  List<DropItem> items, {
  int maxDepth = kMaxUploadDepth,
  int maxFiles = kMaxUploadFiles,
  required Future<http.MultipartFile?> Function(DropItemFile file, String name)
  buildUpload,
  Future<UploadChunkSource?> Function(DropItemFile file)? openChunkSource,
  Future<Uint8List?> Function(DropItemFile file)? renderThumbnail,
}) {
  final uploads = <PendingUpload>[];
  var truncated = false;
  var skippedTooDeep = 0;

  void walk(List<DropItem> level, String relativeDir, int depth) {
    for (final item in level) {
      if (uploads.length >= maxFiles) {
        truncated = true;
        return;
      }

      if (item is DropItemDirectory) {
        if (depth >= maxDepth) {
          skippedTooDeep++;
          continue;
        }
        final childDir = sanitizeRelativeDir('$relativeDir/${item.name}');
        if (childDir == null) {
          continue;
        }
        walk(item.children, childDir, depth + 1);
        continue;
      }

      if (item is! DropItemFile) {
        continue;
      }

      final name = item.name.trim();
      if (name.isEmpty) {
        continue;
      }
      uploads.add(
        PendingUpload(
          relativeDir: relativeDir,
          name: name,
          build: () => buildUpload(item, name),
          openChunkSource: openChunkSource == null
              ? null
              : () => openChunkSource(item),
          renderThumbnail: renderThumbnail == null
              ? null
              : () => renderThumbnail(item),
        ),
      );
    }
  }

  walk(items, '', 0);

  return DropFlattenResult(
    uploads: uploads,
    truncated: truncated,
    skippedTooDeep: skippedTooDeep,
  );
}
