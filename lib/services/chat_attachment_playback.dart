import 'package:flutter/widgets.dart';
import 'package:quark/services/chat_attachment_playback_stub.dart'
    if (dart.library.io) 'package:quark/services/chat_attachment_playback_io.dart'
    if (dart.library.js_interop) 'package:quark/services/chat_attachment_playback_web.dart';

/// Whether a decrypted chat video can be played on this device.
///
/// A native build writes a temporary file. The web plays a blob URL. A
/// platform with neither cannot play one.
bool get chatVideoPlaybackSupported => chatVideoPlaybackSupportedPlatform;

/// Plays [plaintext] and returns when the player route is popped.
///
/// [mime] is the blob type on the web. The temporary file, or the blob URL,
/// is released after the route pops. Throws [UnsupportedError] where
/// [chatVideoPlaybackSupported] is false; check that before opening
/// [plaintext], so a video is not decrypted only to be thrown away.
Future<void> playChatAttachmentVideo({
  required BuildContext context,
  required String name,
  required Stream<List<int>> plaintext,
  String mime = 'video/mp4',
}) => playChatAttachmentVideoPlatform(
  context: context,
  name: name,
  mime: mime,
  plaintext: plaintext,
);
