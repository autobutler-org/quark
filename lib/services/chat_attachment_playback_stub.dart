import 'package:flutter/widgets.dart';

/// A build with nowhere to hand a decrypted video to the player.
bool get chatVideoPlaybackSupportedPlatform => false;

/// Throws [UnsupportedError] without reading [plaintext].
///
/// [mime] is unused. The web player needs it for the blob type.
Future<void> playChatAttachmentVideoPlatform({
  required BuildContext context,
  required String name,
  required Stream<List<int>> plaintext,
  String mime = 'video/mp4',
}) async {
  throw UnsupportedError('This platform cannot play a chat video');
}
