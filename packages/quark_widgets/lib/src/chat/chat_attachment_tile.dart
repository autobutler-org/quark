import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../layout/quark_bar_chip.dart';
import '../layout/quark_bar_icon_button.dart';
import '../models/chat_attachment_item.dart';
import '../theme/quark_tokens.dart';
import '../core/quark_tappable.dart';

/// One file attached to a chat message: a photo, a video, or any other file.
///
/// An image or a video asks [thumbnailBuilder] for a preview. An image with
/// none shows its name. A video is a frame either way: the preview when there
/// is one, and a play control on top. This package does not play the video
/// itself. A file shows its name and its size in B, KiB, or MiB. A tap on an
/// image or a file fires [onOpen]. The play control fires [onPlay].
/// [onSaveToDevice] and [onSaveToFiles], when set, are actions under the
/// preview. Either may be null, and then its action is absent.
///
/// Key prefixes: `chat_attachment_<id>` on the tile,
/// `chat_attachment_play_<id>` on a video's play control,
/// `chat_attachment_save_device_<id>` on save to this device, and
/// `chat_attachment_save_files_<id>` on save to my files.
///
/// ```dart
/// ChatAttachmentTile(
///   item: item,
///   thumbnailBuilder: (context, item) => thumbnailOf(item),
///   onOpen: () => open(item),
///   onPlay: () => play(item),
///   onSaveToDevice: () => saveToDevice(item),
///   onSaveToFiles: () => saveToFiles(item),
/// )
/// ```
class ChatAttachmentTile extends StatelessWidget {
  /// Creates the tile for [item].
  const ChatAttachmentTile({
    required this.item,
    this.thumbnailBuilder,
    this.onOpen,
    this.onPlay,
    this.onSaveToDevice,
    this.onSaveToFiles,
    super.key,
  });

  /// The file to draw.
  final ChatAttachmentItem item;

  /// Builds an image or video preview. Null, or a builder that returns null,
  /// shows an image's name and a video's empty frame. Not called for a file.
  final Widget? Function(BuildContext context, ChatAttachmentItem item)?
  thumbnailBuilder;

  /// Called when an image or a file is tapped. Null leaves that tile inert.
  /// A video's play control does not call this.
  final VoidCallback? onOpen;

  /// Called when a video's play control is tapped. Null leaves the control
  /// disabled.
  final VoidCallback? onPlay;

  /// Called when "Save to device" is tapped. Null leaves that action out.
  final VoidCallback? onSaveToDevice;

  /// Called when "Save to my files" is tapped. Null leaves that action out.
  final VoidCallback? onSaveToFiles;

  static const double _previewHeight = 160;
  static const double _maxWidth = 280;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final item = this.item;
    final preview = item.kind == ChatAttachmentKind.file
        ? null
        : thumbnailBuilder?.call(context, item);
    final name = Text(
      item.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: tokens.foreground),
    );
    final size = Text(
      _formatSize(item.size),
      style: TextStyle(color: tokens.mutedForeground, fontSize: 12),
    );

    final Widget body;
    final VoidCallback? onTap;
    if (item.kind == ChatAttachmentKind.video) {
      // The play control is the button. The frame around it is not a second
      // one, or a screen reader announces two controls for one video.
      onTap = null;
      final frame = preview;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: SizedBox(
              width: double.infinity,
              height: _previewHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: frame ?? ColoredBox(color: tokens.input),
                  ),
                  QuarkBarIconButton(
                    key: ValueKey('chat_attachment_play_${item.id}'),
                    icon: QuarkIcons.play_arrow,
                    tooltip: 'Play',
                    onPressed: onPlay,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: tokens.spacingXs),
          name,
          size,
        ],
      );
    } else if (preview != null) {
      onTap = onOpen;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: SizedBox(
              width: double.infinity,
              height: _previewHeight,
              child: preview,
            ),
          ),
          SizedBox(height: tokens.spacingXs),
          name,
          size,
        ],
      );
    } else {
      onTap = onOpen;
      body = Row(
        children: [
          Icon(
            item.kind == ChatAttachmentKind.image
                ? QuarkIcons.image_outlined
                : QuarkIcons.insert_drive_file_outlined,
            size: 20,
            color: tokens.mutedForeground,
          ),
          SizedBox(width: tokens.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [name, size],
            ),
          ),
        ],
      );
    }

    final saveToDevice = onSaveToDevice;
    final saveToFiles = onSaveToFiles;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.card,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingSm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  button: onTap != null,
                  child: QuarkTappable(
                    key: ValueKey('chat_attachment_${item.id}'),
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    child: ConstrainedBox(
                      // A file row is otherwise shorter than the 48dp tap target.
                      constraints: const BoxConstraints(minHeight: 48),
                      child: body,
                    ),
                  ),
                ),
                if (saveToDevice != null || saveToFiles != null) ...[
                  SizedBox(height: tokens.spacingXs),
                  Wrap(
                    spacing: tokens.spacingXs,
                    runSpacing: tokens.spacingXs,
                    children: [
                      if (saveToDevice != null)
                        QuarkBarChip(
                          key: ValueKey(
                            'chat_attachment_save_device_${item.id}',
                          ),
                          icon: QuarkIcons.download_outlined,
                          label: 'Save to device',
                          tooltip: 'Save to device',
                          keepLabel: true,
                          onPressed: saveToDevice,
                        ),
                      if (saveToFiles != null)
                        QuarkBarChip(
                          key: ValueKey(
                            'chat_attachment_save_files_${item.id}',
                          ),
                          icon: QuarkIcons.folder,
                          label: 'Save to my files',
                          tooltip: 'Save to my files',
                          keepLabel: true,
                          onPressed: saveToFiles,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [bytes] as a short size: B under 1024, then KiB, then MiB.
String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes < 0 ? 0 : bytes} B';
  final (unit, scale) = bytes < 1024 * 1024
      ? ('KiB', 1024)
      : ('MiB', 1024 * 1024);
  final text = (bytes / scale).toStringAsFixed(1);
  final shown = text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  return '$shown $unit';
}
