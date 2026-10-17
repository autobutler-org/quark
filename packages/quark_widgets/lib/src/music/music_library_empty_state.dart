import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';

/// The Music page when the library is scanning or has no indexed tracks.
///
/// [isScanning] selects the progress state; otherwise the widget shows the
/// settled "no music yet" state. Supplying [onScan] adds an explicit scan
/// action for callers allowed to start one.
///
/// Key: `music_scan` on the optional scan button.
///
/// ```dart
/// MusicLibraryEmptyState(
///   isScanning: controller.isScanning,
///   onScan: controller.canRescan ? controller.rescan : null,
/// );
/// ```
class MusicLibraryEmptyState extends StatelessWidget {
  /// Creates the scanning or settled-empty state.
  const MusicLibraryEmptyState({
    this.isScanning = false,
    this.onScan,
    super.key,
  });

  /// Whether the server is currently building the music library.
  final bool isScanning;

  /// Called when Scan music is tapped. Null hides the action.
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    if (isScanning) {
      return Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(tokens.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const QuarkLoader(),
              SizedBox(height: tokens.spacingMd),
              const Text(
                'Scanning your music',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: tokens.spacingSm),
              Text(
                'Looking for audio files on your devices.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.mutedForeground),
              ),
            ],
          ),
        ),
      );
    }

    return EmptyStateWidget(
      icon: QuarkIcons.audio_file_outlined,
      headline: 'No music yet',
      subtext: 'Add audio files to your Quark, then scan the library.',
      action: onScan == null
          ? null
          : FilledButton.icon(
              key: const ValueKey('music_scan'),
              onPressed: onScan,
              icon: const Icon(QuarkIcons.search),
              label: const Text('Scan music'),
            ),
    );
  }
}
