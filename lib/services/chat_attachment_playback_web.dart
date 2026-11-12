import 'dart:js_interop';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/chat/chat_local_video_page.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

/// The web plays a decrypted video from a blob URL.
bool get chatVideoPlaybackSupportedPlatform => true;

/// Collects [plaintext] into a blob of type [mime], plays it, then revokes
/// the URL.
Future<void> playChatAttachmentVideoPlatform({
  required BuildContext context,
  required String name,
  required Stream<List<int>> plaintext,
  String mime = 'video/mp4',
}) async {
  final parts = <JSUint8Array>[];
  await for (final chunk in plaintext) {
    parts.add(Uint8List.fromList(chunk).toJS);
  }
  final blob = web.Blob(parts.toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  try {
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatLocalVideoPage(
          name: name,
          open: () => VideoPlayerController.networkUrl(Uri.parse(url)),
        ),
      ),
    );
  } finally {
    web.URL.revokeObjectURL(url);
  }
}
