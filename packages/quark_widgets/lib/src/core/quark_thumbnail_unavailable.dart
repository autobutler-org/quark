import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';
import '../models/quark_file_kind.dart';
import 'quark_file_icon.dart';

/// Why a file has no thumbnail, when nothing could make one.
enum ThumbnailIssue {
  /// The file is fine, but its format cannot be pictured here: an HEVC,
  /// ProRes or MPEG-TS video in a browser that does not decode it. It may
  /// play or open elsewhere.
  unsupportedFormat,

  /// The file could not be read as what its name says it is: truncated,
  /// damaged, or not a video at all.
  unreadable,

  /// There is no thumbnail to show and nothing left to make one from: the
  /// server answered that it has none, or the file has moved or been deleted.
  missing,

  /// The server would not send the thumbnail, after every retry: busy, or
  /// failing. The file may be fine, and it may load later.
  loadFailed,
}

/// The placeholder for a file whose thumbnail cannot be made, which says so
/// instead of looking like a file that has no thumbnail or one still loading.
///
/// Draws the glyph for the file's [kind] ([QuarkFileIcon], so a video still
/// reads as a video) with a badge for the [issue]: a crossed-out eye for a format that
/// cannot be previewed, a broken picture for a file that could not be read,
/// a question mark for a thumbnail that is gone, and a crossed-out cloud for
/// one the server would not send.
/// [reason] is the sentence that explains it, written by the caller: it is
/// the tooltip on hover and what a screen reader announces. Given [label]
/// and room for it (a grid tile rather than a list row's leading slot), the
/// short label is written under the glyph as well, so a touch user sees it
/// without a gesture.
///
/// The tooltip shows on hover only. A long-press on the tile around it keeps
/// opening the tile's menu.
///
/// Probe key: `thumbnail_unavailable_<name>` on the badge.
///
/// ```dart
/// QuarkThumbnailUnavailable(
///   name: 'clip.mov',
///   kind: QuarkFileKind.video,
///   issue: ThumbnailIssue.unsupportedFormat,
///   reason: "This video's format can't be previewed on this device.",
///   label: 'No preview',
/// )
/// ```
class QuarkThumbnailUnavailable extends StatelessWidget {
  /// Creates the placeholder for the file called [name].
  const QuarkThumbnailUnavailable({
    required this.name,
    required this.kind,
    required this.issue,
    required this.reason,
    this.label,
    this.iconSize = 20,
    super.key,
  });

  /// The file's name, which keys the badge.
  final String name;

  /// What the file is, which picks its glyph.
  final QuarkFileKind kind;

  /// Why there is no thumbnail, which picks the badge.
  final ThumbnailIssue issue;

  /// The sentence explaining [issue], shown on hover and read by a screen
  /// reader.
  final String reason;

  /// A few words for [issue], written under the glyph when there is room.
  /// Null writes nothing.
  final String? label;

  /// The glyph's size in logical pixels; the badge scales with it.
  final double iconSize;

  /// The smallest height that fits [label] under the glyph.
  double get _labelHeight => iconSize + 40;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final badgeSize = iconSize * 0.55;
    final glyph = SizedBox(
      width: iconSize + badgeSize / 2,
      height: iconSize + badgeSize / 2,
      child: Stack(
        children: [
          QuarkFileIcon(
            kind: kind,
            size: iconSize,
            color: tokens.mutedForeground,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              key: ValueKey('thumbnail_unavailable_$name'),
              decoration: BoxDecoration(
                color: tokens.card,
                shape: BoxShape.circle,
              ),
              child: Icon(
                switch (issue) {
                  ThumbnailIssue.unsupportedFormat => QuarkIcons.visibility_off,
                  ThumbnailIssue.unreadable => QuarkIcons.broken_image,
                  ThumbnailIssue.missing => QuarkIcons.help_outline,
                  ThumbnailIssue.loadFailed => QuarkIcons.cloud_off_outlined,
                },
                size: badgeSize,
                // Only a damaged file is cause for concern.
                color: issue == ThumbnailIssue.unreadable
                    ? tokens.warning
                    : tokens.secondaryForeground,
              ),
            ),
          ),
        ],
      ),
    );
    return Tooltip(
      message: reason,
      triggerMode: TooltipTriggerMode.manual,
      excludeFromSemantics: true,
      child: Semantics(
        label: reason,
        child: ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final text = label;
              final showLabel =
                  text != null && constraints.maxHeight >= _labelHeight;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    glyph,
                    if (showLabel) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.mutedForeground,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
