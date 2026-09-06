import 'package:quark/utils/folder_picker_io.dart'
    if (dart.library.js_interop) 'package:quark/utils/folder_picker_web.dart'
    as platform;
import 'package:quark/utils/upload_tree_utils.dart';

export 'ios_photo_library.dart';

/// Whether this platform can offer folder selection.
///
/// Web and desktop can. Mobile has no meaningful folder picker, so callers
/// hide the affordance rather than offering one that cannot work.
bool get isFolderPickerSupported => platform.isFolderPickerSupportedPlatform;

/// Whether this client must offer Photos as a source separate from Files.
///
/// iOS is the only platform whose document picker is the Files app and cannot
/// see the Camera Roll. Safari, the installed PWA, and the native app all
/// need a second picker pointed at the Photos library (#1797).
bool get isPhotoLibraryPickerNeeded =>
    platform.isPhotoLibraryPickerNeededPlatform;

/// Prompts for a folder and returns its files, each carrying the directory it
/// sat in relative to the chosen folder.
///
/// Returns an empty list when the user cancels or the folder holds no files.
Future<List<PendingUpload>> pickFolderUploads() {
  return platform.pickFolderUploadsPlatform();
}

/// Prompts for one or more files.
///
/// Split by platform for the same reason the folder picker is: what each
/// platform can hand back differs, and on the web the difference decides
/// whether a large file fits in the tab at all (#1629). Supported everywhere,
/// unlike folder selection.
Future<List<PendingUpload>> pickFileUploads() {
  return platform.pickFileUploadsPlatform();
}

/// Prompts for photos and videos from the device library.
///
/// On the web this is an `<input accept="image/*,video/*">`, which is what
/// makes iOS Safari open Photos instead of Files. On native iOS it is
/// `FileType.media`. Same [PendingUpload] shape as [pickFileUploads], so the
/// upload manager does not care which source the bytes came from.
Future<List<PendingUpload>> pickPhotoUploads() {
  return platform.pickPhotoUploadsPlatform();
}
