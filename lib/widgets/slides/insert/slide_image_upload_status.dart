import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A strip over the slide canvas while a picture uploads (#1158): which
/// file, and how much of it has gone, as a determinate bar that a screen
/// reader hears as a percentage.
///
/// Key prefixes: `slide_image_upload` on the strip.
class SlideImageUploadStatus extends StatelessWidget {
  /// The upload of [name], [progress] of the way there (0 to 1).
  const SlideImageUploadStatus({
    required this.name,
    required this.progress,
    super.key,
  });

  /// The file being uploaded.
  final String name;

  /// How much has been sent, 0 to 1.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final percent = (progress * 100).round();
    return Container(
      key: const ValueKey('slide_image_upload'),
      color: tokens.card,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacingMd,
        vertical: tokens.spacingSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: tokens.spacingXs,
        children: [
          Text(
            'Uploading $name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.foreground),
          ),
          LinearProgressIndicator(
            value: progress,
            semanticsLabel: 'Uploading $name',
            semanticsValue: '$percent%',
          ),
        ],
      ),
    );
  }
}
