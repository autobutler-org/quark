import 'package:flutter/material.dart';

import '../models/transcode_format_option.dart';
import '../models/transcode_quality.dart';
import '../theme/quark_tokens.dart';

/// A dialog for converting a video: choose a quality and a target format.
///
/// It never loads: [formats], [isLoading], and [error] come in, and the caller
/// loads again when [onRetry] fires. The chosen format and quality are [State]
/// because they are the form's own transient input, thrown away when the
/// dialog closes; the one outcome that matters leaves through [onConvert].
///
/// At [TranscodeQuality.original] the video's own format, [sourceFormat], is
/// shown but disabled, since converting to it would only copy the file.
/// Choosing it at [TranscodeQuality.small] and then switching back to original
/// clears the choice. Chips carry no checkmark and every quality description
/// reserves the same height, so nothing in the dialog moves under a tap.
///
/// Key prefixes: `transcode_quality_<quality>` on each quality chip,
/// `transcode_format_<format>` on each format chip, `transcode_convert`,
/// `transcode_cancel`, and `transcode_retry`, rendered only with an [error].
///
/// ```dart
/// showDialog<(String, TranscodeQuality)>(
///   context: context,
///   builder: (context) => TranscodeDialog(
///     formats: formats,
///     sourceFormat: 'mov',
///     onConvert: (format, quality) =>
///         Navigator.of(context).pop((format, quality)),
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

  /// Called with the chosen format and quality when the convert button is
  /// tapped. The button is disabled until a format is chosen.
  final void Function(String format, TranscodeQuality quality) onConvert;

  /// Called when the cancel button is tapped.
  final VoidCallback onCancel;

  /// Called when the retry button under an [error] is tapped.
  final VoidCallback onRetry;

  /// The video's own format, the extension without the dot, compared without
  /// regard to case. Null offers every format at every quality.
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
  TranscodeQuality _quality = TranscodeQuality.original;

  bool _offered(String format) =>
      _quality != TranscodeQuality.original ||
      format.toLowerCase() != widget.sourceFormat?.toLowerCase();

  void _chooseQuality(TranscodeQuality quality) {
    setState(() {
      _quality = quality;
      final format = _format;
      if (format != null && !_offered(format)) _format = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurface.withValues(alpha: 0.5),
    );
    final error = widget.error;
    final offered = [
      for (final option in widget.formats)
        if (_offered(option.format)) option,
    ];
    final chosen = _format;
    final canConvert =
        !widget.isLoading &&
        error == null &&
        offered.any((option) => option.format == chosen);

    return AlertDialog(
      title: const Text('Convert video'),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quality', style: labelStyle),
            SizedBox(height: tokens.spacingXs),
            Wrap(
              spacing: tokens.spacingSm,
              runSpacing: tokens.spacingXs,
              children: [
                for (final quality in TranscodeQuality.values)
                  ChoiceChip(
                    key: ValueKey('transcode_quality_${quality.name}'),
                    label: Text(quality.label),
                    selected: _quality == quality,
                    // A checkmark would widen the chosen chip and reflow the row.
                    showCheckmark: false,
                    onSelected: (_) => _chooseQuality(quality),
                  ),
              ],
            ),
            SizedBox(height: tokens.spacingXs),
            // Every description is laid out so the tallest sets the height,
            // and switching quality never moves what sits below.
            Stack(
              children: [
                for (final quality in TranscodeQuality.values)
                  Visibility(
                    visible: _quality == quality,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Text(quality.description),
                  ),
              ],
            ),
            SizedBox(height: tokens.spacingMd),
            Text('Format', style: labelStyle),
            SizedBox(height: tokens.spacingXs),
            if (widget.isLoading)
              Padding(
                padding: EdgeInsets.all(tokens.spacingMd),
                child: const Center(child: CircularProgressIndicator()),
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
                      showCheckmark: false,
                      // Disabled rather than removed, so switching quality
                      // never adds or drops a chip from the row.
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
          onPressed: canConvert && chosen != null
              ? () => widget.onConvert(chosen, _quality)
              : null,
          child: const Text('Convert'),
        ),
      ],
    );
  }
}
