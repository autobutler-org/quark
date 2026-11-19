import 'package:material_ui/material_ui.dart';
import 'package:quark/models/album_export.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// How a photo export ended (#3501). Only an export that copied every photo
/// says it finished; a partial one says so and lists the photos left out by
/// name, with why; one that stopped without a list says it stopped.
///
/// Key prefixes: `export_result_message` on the sentence, and
/// `export_failure_<index>` on each photo that was not copied.
class ExportResultView extends StatelessWidget {
  /// Creates the view over [summary], or [error] when the result couldn't be
  /// read.
  const ExportResultView({
    required this.driveName,
    this.summary,
    this.error,
    super.key,
  });

  /// The drive the export folder is on.
  final String driveName;

  /// How the export ended.
  final AlbumExportSummary? summary;

  /// Copy for a result that couldn't be read.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final summary = this.summary;
    final String message;
    if (summary == null) {
      message = error ?? Errors.exportStopped;
    } else if (summary.isComplete) {
      final files = summary.copied == 1 ? '1 file' : '${summary.copied} files';
      message =
          'The export is finished. $files went to the folder '
          '"${summary.relPath}" on $driveName.';
    } else if (summary.failedCount > 0) {
      message = Errors.exportPartial(
        failed: summary.failedCount,
        copied: summary.copied,
      );
    } else {
      message = Errors.exportStopped;
    }
    final failures = summary?.failures ?? const <AlbumExportFailure>[];
    final more = summary?.moreFailures ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, key: const ValueKey('export_result_message')),
        if (failures.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'These photos were not copied:',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: failures.length,
              itemBuilder: (context, index) {
                final failure = failures[index];
                return ListTile(
                  key: ValueKey('export_failure_$index'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    QuarkIcons.error_outline,
                    color: tokens.error,
                    size: 20,
                  ),
                  title: Text(failure.name),
                  subtitle: Text(
                    Errors.exportFailureReason(
                      missing:
                          failure.reason == AlbumExportFailureReason.missing,
                    ),
                  ),
                );
              },
            ),
          ),
          if (more > 0)
            Text(more == 1 ? 'And 1 more photo.' : 'And $more more photos.'),
        ],
      ],
    );
  }
}
