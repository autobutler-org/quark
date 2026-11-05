import 'package:flutter/widgets.dart';
import 'package:quark/services/chat_attachment_playback_stub.dart'
    if (dart.library.io) 'package:quark/services/chat_attachment_playback_io.dart';

/// Whether a decrypted chat video can be written to a local file and played.
///
/// False on the web, which has no file for the video player to open.
bool get chatVideoPlaybackSupported => chatVideoPlaybackSupportedPlatform;

/// Writes [plaintext] to a temporary file and plays it.
///
/// Returns when the player route is popped. The temporary file is removed
/// then. Throws [UnsupportedError] where [chatVideoPlaybackSupported] is
/// false; check that before opening [plaintext], so a video is not decrypted
/// only to be thrown away.
Future<void> playChatAttachmentVideo({
  required BuildContext context,
  required String name,
  required Stream<List<int>> plaintext,
}) => playChatAttachmentVideoPlatform(
  context: context,
  name: name,
  plaintext: plaintext,
);
