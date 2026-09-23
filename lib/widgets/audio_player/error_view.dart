import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The audio player's failure state: why it could not play, and a way to
/// download the file instead.
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onDownload;
  final bool downloading;

  const ErrorView({
    super.key,
    required this.message,
    required this.onDownload,
    required this.downloading,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.audio_file_outlined, size: 48),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: downloading ? null : onDownload,
            icon: downloading
                ? const QuarkLoader(size: 16)
                : const Icon(Icons.download_rounded, size: 16),
            label: Text(downloading ? 'Downloading…' : 'Download'),
          ),
        ],
      ),
    );
  }
}
