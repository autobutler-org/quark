import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/chat/chat_local_video_page.dart';
import 'package:video_player/video_player.dart';

/// A decrypted chat video can be written to a temp file and played.
bool get chatVideoPlaybackSupportedPlatform => true;

/// Writes [plaintext] to a temp file, plays it, then deletes the file.
///
/// [mime] is unused here. The web player needs it for the blob type.
Future<void> playChatAttachmentVideoPlatform({
  required BuildContext context,
  required String name,
  required Stream<List<int>> plaintext,
  String mime = 'video/mp4',
}) async {
  final dir = await Directory.systemTemp.createTemp('quark-chat-');
  try {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final fileName = safe.isEmpty || safe == '.' || safe == '..'
        ? 'video'
        : safe;
    final file = File('${dir.path}/$fileName');
    final raf = await file.open(mode: FileMode.write);
    try {
      await for (final chunk in plaintext) {
        await raf.writeFrom(chunk);
      }
    } finally {
      await raf.close();
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatLocalVideoPage(
          name: name,
          open: () => VideoPlayerController.file(File(file.path)),
        ),
      ),
    );
  } finally {
    try {
      await dir.delete(recursive: true);
    } on Object {
      // The player has released the file. If the platform still holds it,
      // leaving the temp directory is better than failing the play that
      // already finished.
    }
  }
}
