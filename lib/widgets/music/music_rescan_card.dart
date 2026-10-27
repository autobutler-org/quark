import 'package:flutter/material.dart';
import 'package:quark/models/job.dart';
import 'package:quark/services/music_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The admin's "Rescan music library" action in Settings (#3283): it
/// queues the `music_rescan` job, whose progress shows in the jobs badge,
/// and says so.
///
/// The library keeps itself current as files change, so this is for a
/// library that looks wrong: tags edited elsewhere, or a drive whose files
/// changed while it was unplugged.
///
/// Keys: `settings_music_rescan` on the button, `settings_music_rescan_error`
/// on the failure line, `settings_music_rescan_queued` on the confirmation.
class MusicRescanCard extends StatefulWidget {
  /// Creates the card. [rescan] defaults to the real service; tests pass a
  /// fake.
  const MusicRescanCard({this.rescan = MusicService.rescan, super.key});

  /// Queues the rescan.
  final Future<Job> Function() rescan;

  @override
  State<MusicRescanCard> createState() => _MusicRescanCardState();
}

class _MusicRescanCardState extends State<MusicRescanCard> {
  bool _busy = false;
  bool _queued = false;
  Object? _error;

  Future<void> _rescan() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    Object? error;
    try {
      await widget.rescan();
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _queued = error == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = _error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Music library',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Music keeps itself up to date as files change. Rescan if '
              'songs are missing or show old details.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('settings_music_rescan'),
              onPressed: _busy ? null : _rescan,
              icon: _busy
                  ? const QuarkLoader(size: 16)
                  : const Icon(QuarkIcons.library_music_outlined),
              label: const Text('Rescan music library'),
            ),
            if (_queued) ...[
              const SizedBox(height: 8),
              const Text(
                'Scan started. Its progress shows in Jobs.',
                key: ValueKey('settings_music_rescan_queued'),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                Errors.message(error, 'start a music scan'),
                key: const ValueKey('settings_music_rescan_error'),
                style: TextStyle(color: tokens.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
