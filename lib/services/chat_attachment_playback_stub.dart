import 'package:flutter/widgets.dart';

/// Web and any other build with no local file a video player can open.
bool get chatVideoPlaybackSupportedPlatform => false;

/// Throws [UnsupportedError] without reading [plaintext].
Future<void> playChatAttachmentVideoPlatform({
  required BuildContext context,
  required String name,
  required Stream<List<int>> plaintext,
}) async {
  throw UnsupportedError('This platform cannot play a chat video from a file');
}
