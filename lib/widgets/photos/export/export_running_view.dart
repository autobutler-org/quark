import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The export dialog while the Quark copies (#3501): where the export is
/// going, how far it has got, and that the dialog can be closed because the
/// export carries on and shows in Jobs.
///
/// Key prefixes: `export_destination` on where it is going and
/// `export_progress` on the bar.
class ExportRunningView extends StatelessWidget {
  /// Creates the view.
  const ExportRunningView({
    required this.driveName,
    required this.relPath,
    required this.progress,
    this.isStarting = false,
    super.key,
  });

  /// The drive the export folder is on.
  final String driveName;

  /// The export folder, or the folder chosen while [isStarting].
  final String relPath;

  /// How far the copying is, from 0 to 1.
  final double progress;

  /// Whether the Quark has yet to answer that it started.
  final bool isStarting;

  /// What the view says about following the export once the dialog closes.
  static const String followInJobs =
      'You can close this window. The export carries on, and you can follow '
      'it in Jobs, under System.';

  @override
  Widget build(BuildContext context) {
    if (isStarting) {
      return const Row(
        children: [
          QuarkLoader(size: 20),
          SizedBox(width: 12),
          Expanded(child: Text('Starting the export…')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Copying your photos to the folder "$relPath" on $driveName.',
          key: const ValueKey('export_destination'),
        ),
        const SizedBox(height: 16),
        // The job reports a real fraction, so this is the determinate bar.
        LinearProgressIndicator(
          key: const ValueKey('export_progress'),
          value: progress,
        ),
        const SizedBox(height: 16),
        const Text(followInJobs),
      ],
    );
  }
}
