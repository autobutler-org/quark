import 'package:quark/services/chat_attachment_save_io.dart'
    if (dart.library.js_interop) 'package:quark/services/chat_attachment_save_web.dart'
    as platform;

/// Saves decrypted attachment [plaintext] as [fileName] through the platform
/// save, and returns where it landed, or null when the person canceled.
///
/// On a phone a picture or video goes to the photo library, and anything else
/// through the save dialog, the same path as other downloads (#3334). The
/// desktop asks where to put the file. The web downloads it through the
/// browser. The plaintext is not collected into one list where the platform
/// can save a file.
Future<String?> saveChatAttachmentToDevice({
  required Stream<List<int>> plaintext,
  required String fileName,
}) => platform.saveChatAttachmentToDevicePlatform(
  plaintext: plaintext,
  fileName: fileName,
);

/// Uploads decrypted attachment [plaintext] into [folder] as [fileName].
///
/// [folder] is a Quark files path, `/` for the top. A name already in that
/// folder is kept, and this file lands beside it. Where the platform has a
/// filesystem, the plaintext is written to a temporary file and uploaded from
/// that path, then the file is deleted.
Future<void> uploadChatAttachmentToFolder({
  required Stream<List<int>> plaintext,
  required String folder,
  required String fileName,
}) => platform.uploadChatAttachmentToFolderPlatform(
  plaintext: plaintext,
  folder: folder,
  fileName: fileName,
);
