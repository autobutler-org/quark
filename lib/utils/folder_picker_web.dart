import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/upload_chunk_source_web.dart';
import 'package:quark/utils/ios_photo_library.dart';
import 'package:quark/utils/upload_tree_utils.dart';
import 'package:web/web.dart' as web;

/// Browsers have supported directory selection for over a decade.
///
/// `webkitdirectory` is non-standard in name only — Chrome, Firefox, Safari
/// and Edge all implement it, and each selected file exposes
/// `webkitRelativePath` giving its path inside the chosen folder. That is
/// exactly the structure needed to rebuild `rootDir`, and it is why this goes
/// straight to the DOM instead of through file_picker, whose PlatformFile
/// does not surface the property at all.
bool get isFolderPickerSupportedPlatform => true;

/// Safari, the PWA, and iPadOS "desktop" mode. See [isIosPhotoLibraryClient].
bool get isPhotoLibraryPickerNeededPlatform {
  final nav = web.window.navigator;
  return isIosPhotoLibraryClient(
    userAgent: nav.userAgent,
    platform: nav.platform,
    maxTouchPoints: nav.maxTouchPoints,
  );
}

Future<List<PendingUpload>> pickFolderUploadsPlatform() {
  return _pickUploads(directory: true);
}

/// Plain file selection, also straight to the DOM rather than through
/// file_picker.
///
/// file_picker's web backend has no setting that hands back a lazy handle:
/// `withData: true` reads every byte into the heap, and `withData: false` is
/// worse — it base64s the whole file into a data URL. Either way a large file
/// is in memory before it is sent, which is the third of the three places
/// #1629 had to fix. An `<input type="file">` gives us the `File` objects
/// themselves, and a `File` is a `Blob`: sliceable, and read only when
/// something consumes the slice.
///
/// No `accept` on purpose: on iOS a missing accept (with `multiple`) is what
/// opens the Files app. Photos is a separate entry point (#1797).
Future<List<PendingUpload>> pickFileUploadsPlatform() {
  return _pickUploads(directory: false);
}

/// Photos library selection.
///
/// `accept="image/*,video/*"` is the switch that makes iOS Safari open the
/// Camera Roll instead of Files. `capture` is deliberately not set — that
/// attribute skips the library and opens the camera.
Future<List<PendingUpload>> pickPhotoUploadsPlatform() {
  return _pickUploads(directory: false, accept: kPhotoUploadAccept);
}

Future<List<PendingUpload>> _pickUploads({
  required bool directory,
  String? accept,
}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..style.display = 'none';
  if (directory) {
    input.setAttribute('webkitdirectory', 'true');
  }
  if (accept != null && accept.isNotEmpty) {
    input.accept = accept;
  }
  web.document.body?.append(input);

  final completer = Completer<List<PendingUpload>>();
  void finish(List<PendingUpload> uploads) {
    if (!completer.isCompleted) {
      completer.complete(uploads);
    }
  }

  input.onchange = ((web.Event _) {
    finish(_uploadsFromInput(input));
  }).toJS;
  // Fired when the picker is dismissed without choosing anything. Browsers
  // that predate the cancel event simply leave the future pending until the
  // user picks something, which is the same as today's file picker.
  input.oncancel = ((web.Event _) {
    finish(const []);
  }).toJS;

  input.click();

  try {
    return await completer.future;
  } finally {
    input.remove();
  }
}

List<PendingUpload> _uploadsFromInput(web.HTMLInputElement input) {
  final files = input.files;
  if (files == null || files.length == 0) {
    return const [];
  }

  final uploads = <PendingUpload>[];
  for (var i = 0; i < files.length; i++) {
    if (uploads.length >= kMaxUploadFiles) {
      break;
    }
    final file = files.item(i);
    if (file == null) {
      continue;
    }

    // webkitRelativePath is 'chosenFolder/sub/file.txt'. It is empty when the
    // browser gave us a plain file selection instead of a directory one, in
    // which case the file belongs at the upload root.
    final relativePath = file.webkitRelativePath.isNotEmpty
        ? file.webkitRelativePath
        : file.name;
    final relativeDir = sanitizeRelativeDir(relativeDirOf(relativePath));
    if (relativeDir == null) {
      continue;
    }

    final name = file.name.trim();
    if (name.isEmpty) {
      continue;
    }

    uploads.add(
      PendingUpload(
        relativeDir: relativeDir,
        name: name,
        build: () async {
          try {
            // Only ever reached below the chunking threshold — a large file
            // goes out slice by slice through the chunk source instead, and
            // never lands here whole (#1629).
            final buffer = await file.arrayBuffer().toDart;
            return http.MultipartFile.fromBytes(
              'files',
              buffer.toDart.asUint8List(),
              filename: name,
            );
          } catch (e) {
            debugPrint('[folder_picker_web.dart] Failed to read $name: $e');
            return null;
          }
        },
        // A File is a Blob, so the chunk source is a handle on bytes the
        // browser already holds — nothing is read here.
        openChunkSource: () async => BlobUploadChunkSource(
          file,
          lastModified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
        ),
      ),
    );
  }

  return uploads;
}
