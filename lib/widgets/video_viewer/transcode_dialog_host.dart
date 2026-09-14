import 'package:flutter/material.dart';
import 'package:quark/models/transcode_format.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Opens the package's [TranscodeDialog] and feeds it the formats from
/// [loadFormats], retrying on request.
///
/// The load is injected rather than called here, so this widget holds the
/// dialog's loading state without knowing a service exists. [show] answers
/// with the chosen format and quality, or null when canceled.
class TranscodeDialogHost extends StatefulWidget {
  /// Creates the host for a video whose own format is [sourceFormat].
  const TranscodeDialogHost({
    required this.loadFormats,
    this.sourceFormat,
    super.key,
  });

  /// Shows the dialog and answers with the format and quality chosen, or null.
  static Future<(String, TranscodeQuality)?> show(
    BuildContext context, {
    required Future<List<TranscodeFormat>> Function() loadFormats,
    String? sourceFormat,
  }) {
    return showDialog<(String, TranscodeQuality)>(
      context: context,
      builder: (_) => TranscodeDialogHost(
        loadFormats: loadFormats,
        sourceFormat: sourceFormat,
      ),
    );
  }

  /// Fetches the formats this Quark can convert to.
  final Future<List<TranscodeFormat>> Function() loadFormats;

  /// The video's own format, the extension without the dot, or null.
  final String? sourceFormat;

  @override
  State<TranscodeDialogHost> createState() => _TranscodeDialogHostState();
}

class _TranscodeDialogHostState extends State<TranscodeDialogHost> {
  List<TranscodeFormatOption> _formats = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final formats = await widget.loadFormats();
      if (!mounted) return;
      setState(() {
        _formats = [
          for (final f in formats)
            TranscodeFormatOption(format: f.format, label: f.label),
        ];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Errors.transcode(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TranscodeDialog(
      formats: _formats,
      sourceFormat: widget.sourceFormat,
      isLoading: _loading,
      error: _error,
      onConvert: (format, quality) =>
          Navigator.of(context).pop((format, quality)),
      onCancel: () => Navigator.of(context).pop(),
      onRetry: _load,
    );
  }
}
