import 'package:flutter/material.dart';

import '../core/quark_loader.dart';
import '../models/transcode_format_option.dart';
import '../theme/quark_tokens.dart';

/// A dialog for converting a video: choose a target format.
///
/// A conversion copies the video's streams into the new container, so there
/// is no quality to choose. It never loads: [formats], [isLoading], and
/// [error] come in, and the caller loads again when [onRetry] fires. The
/// chosen format is [State] because it is the form's own transient input,
/// thrown away when the dialog closes; the one outcome that matters leaves
/// through [onConvert].
///
/// The video's own format, [sourceFormat], is shown but disabled, since
/// converting to it would only copy the file. Chips carry no checkmark, so
/// nothing in the dialog moves under a tap.
///
/// Key prefixes: `transcode_format_<format>` on each format chip,
/// `transcode_convert`, `transcode_cancel`, and `transcode_retry`, rendered
/// only with an [error].
///
/// ```dart
/// showDialog<String>(
///   context: context,
///   builder: (context) => TranscodeDialog(
///     formats: formats,
///     sourceFormat: 'mp4',
///     onConvert: (format) => Navigator.of(context).pop(format),
///     onCancel: () => Navigator.of(context).pop(),
///     onRetry: reload,
///   ),
/// );
/// ```
class TranscodeDialog extends StatefulWidget {
  /// Creates the dialog offering [formats].
  const TranscodeDialog({
    required this.formats,
    required this.onConvert,
    required this.onCancel,
    required this.onRetry,
    this.sourceFormat,
    this.isLoading = false,
    this.error,
    super.key,
  });

  /// The formats the video can be converted to, in the order to offer them.
  final List<TranscodeFormatOption> formats;

  /// Called with the chosen format when the convert button is tapped. The
  /// button is disabled until a format is chosen.
  final ValueChanged<String> onConvert;

  /// Called when the cancel button is tapped.
  final VoidCallback onCancel;

  /// Called when the retry button under an [error] is tapped.
  final VoidCallback onRetry;

  /// The video's own format, the extension without the dot, compared without
  /// regard to case. Null offers every format.
  final String? sourceFormat;

  /// Whether the formats are loading, which shows a spinner in their place.
  final bool isLoading;

  /// A user-facing message for a load that failed, or null.
  final String? error;

  @override
  State<TranscodeDialog> createState() => _TranscodeDialogState();
}

class _TranscodeDialogState extends State<TranscodeDialog> {
  String? _format;

  bool _offered(String format) =>
      format.toLowerCase() != widget.sourceFormat?.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurface.withValues(alpha: 0.5),
    );
    final error = widget.error;
    final chosen = _format;
    final canConvert =
        !widget.isLoading &&
        error == null &&
        chosen != null &&
        widget.formats.any((o) => o.format == chosen && _offered(o.format));

    return AlertDialog(
      title: const Text('Convert video'),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The video is copied into the new format as it is: quick, '
              'and at full quality.',
            ),
            SizedBox(height: tokens.spacingMd),
            Text('Format', style: labelStyle),
            SizedBox(height: tokens.spacingXs),
            if (widget.isLoading)
              Padding(
                padding: EdgeInsets.all(tokens.spacingMd),
                child: const Center(child: QuarkLoader()),
              )
            else if (error != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(error),
                  SizedBox(height: tokens.spacingXs),
                  TextButton(
                    key: const ValueKey('transcode_retry'),
                    onPressed: widget.onRetry,
                    child: const Text('Retry'),
                  ),
                ],
              )
            else if (!widget.formats.any((o) => _offered(o.format)))
              const Text('There are no formats to convert this video to.')
            else
              Wrap(
                spacing: tokens.spacingSm,
                runSpacing: tokens.spacingXs,
                children: [
                  for (final option in widget.formats)
                    ChoiceChip(
                      key: ValueKey('transcode_format_${option.format}'),
                      label: Text(option.label),
                      selected: chosen == option.format,
                      // A checkmark would widen the chosen chip and reflow the row.
                      showCheckmark: false,
                      onSelected: _offered(option.format)
                          ? (_) => setState(() => _format = option.format)
                          : null,
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('transcode_cancel'),
          onPressed: widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('transcode_convert'),
          onPressed: canConvert ? () => widget.onConvert(chosen) : null,
          child: const Text('Convert'),
        ),
      ],
    );
  }
}
