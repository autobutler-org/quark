import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The picture for a chat image whose message carried no thumbnail.
///
/// [load] decrypts the file. The tile gives this a fixed frame, so the bytes
/// fill that frame. A failure draws the image glyph and the same sentence
/// [Errors.message] uses for opening an image.
class ChatAttachmentPreview extends StatefulWidget {
  /// Creates a preview that loads itself from [load].
  const ChatAttachmentPreview({required this.load, super.key});

  /// Decrypts the image. Called once.
  final Future<Uint8List> Function() load;

  @override
  State<ChatAttachmentPreview> createState() => _ChatAttachmentPreviewState();
}

class _ChatAttachmentPreviewState extends State<ChatAttachmentPreview> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.load();
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = Errors.message(error, 'open the image'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return ColoredBox(
      color: tokens.input,
      child: Center(
        child: _error == null
            ? const QuarkLoader(size: 20)
            : Icon(
                QuarkIcons.image_outlined,
                size: 20,
                color: tokens.mutedForeground,
              ),
      ),
    );
  }
}
