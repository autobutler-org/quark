import 'package:material_ui/material_ui.dart';
import 'package:quark/services/music_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The admin's "Rescan music library" card in Settings' Maintenance group
/// (#3283). Queues a scan of every drive's music; the scan's progress shows
/// in the jobs badge like any other job.
///
/// Key prefixes: `rescan_music_button`, and `rescan_music_status` on the line
/// that says it was queued or why it was not.
class RescanMusicSection extends StatefulWidget {
  /// Creates the card. [rescan] is for tests; it queues the real scan when
  /// left out.
  const RescanMusicSection({this.rescan = MusicService.rescan, super.key});

  /// Queues the scan.
  final Future<void> Function() rescan;

  @override
  State<RescanMusicSection> createState() => _RescanMusicSectionState();
}

class _RescanMusicSectionState extends State<RescanMusicSection> {
  bool _busy = false;
  String? _status;

  Future<void> _rescan() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    String status;
    try {
      await widget.rescan();
      status = 'Scan queued. Its progress shows in Jobs.';
    } catch (e) {
      status = Errors.message(e, 'rescan the music library');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return SettingsCallout(
      title: 'Music library',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Look through every drive for music again, if a song is missing '
            'from Music.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('rescan_music_button'),
            onPressed: _busy ? null : _rescan,
            icon: const Icon(QuarkIcons.music_note),
            label: const Text('Rescan music library'),
          ),
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(status, key: const ValueKey('rescan_music_status')),
          ],
        ],
      ),
    );
  }
}
