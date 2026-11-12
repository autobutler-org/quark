import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The picture for a chat attachment whose message carried no thumbnail.
///
/// [load] produces image bytes: the photo itself, or one frame of a video.
/// The tile gives this a fixed frame, so the bytes fill that frame. A null
/// result leaves the frame blank. When [reportFailure] is set, a thrown
/// error draws the image glyph instead.
class ChatAttachmentPreview extends StatefulWidget {
  /// Creates a preview that loads itself from [load].
  const ChatAttachmentPreview({
    required this.load,
    this.reportFailure = true,
    super.key,
  });

  /// Decrypts or renders the preview. Called once. Null means there is no
  /// picture to show.
  final Future<Uint8List?> Function() load;

  /// Whether a thrown [load] draws the image glyph. A video leaves this
  /// false so a decoder miss stays an empty frame under the play control.
  final bool reportFailure;

  @override
  State<ChatAttachmentPreview> createState() => _ChatAttachmentPreviewState();
}

class _ChatAttachmentPreviewState extends State<ChatAttachmentPreview> {
  Uint8List? _bytes;
  String? _error;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.load();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _settled = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _settled = true;
        if (widget.reportFailure) {
          _error = Errors.message(error, 'open the image');
        }
      });
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
    final error = _error;
    return ColoredBox(
      color: tokens.input,
      child: Center(
        child: !_settled
            ? const QuarkLoader(size: 20)
            : error == null
            ? const SizedBox.shrink()
            : Icon(
                QuarkIcons.image_outlined,
                size: 20,
                color: tokens.mutedForeground,
              ),
      ),
    );
  }
}
