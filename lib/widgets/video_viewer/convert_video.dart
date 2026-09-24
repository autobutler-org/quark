import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/models/transcode_format.dart';
import 'package:quark/router.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/video_viewer/transcode_dialog_host.dart';

/// Queues a conversion of [relPath] — [FilesService.transcodeVideo].
typedef TranscodeVideoFn =
    Future<int> Function(
      String relPath, {
      String? serial,
      required String format,
      required String quality,
    });

/// Converts the video at [relPath] on the device [serial]: asks for a format
/// and quality in the [TranscodeDialogHost], queues the job, and says so in a
/// snack bar whose View opens the Jobs page. A refusal shows as a snack bar
/// too. The video viewer and the Files menu both run this.
///
/// [loadFormats] and [transcode] default to the real calls and are injectable
/// so a test can fake them.
Future<void> convertVideo(
  BuildContext context, {
  required String relPath,
  String? serial,
  Future<List<TranscodeFormat>> Function() loadFormats =
      FilesService.listTranscodeFormats,
  TranscodeVideoFn transcode = FilesService.transcodeVideo,
}) async {
  final fileName = relPath.split('/').last;
  final dot = fileName.lastIndexOf('.');
  final choice = await TranscodeDialogHost.show(
    context,
    loadFormats: loadFormats,
    sourceFormat: dot <= 0 ? null : fileName.substring(dot + 1),
  );
  if (choice == null || !context.mounted) return;
  final (format, quality) = choice;
  try {
    await transcode(
      relPath,
      serial: serial,
      format: format,
      quality: quality.name,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Conversion started'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            if (!context.mounted) return;
            context.go(AppRoutes.systemTab(SystemTab.jobs));
          },
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(Errors.transcode(e))));
  }
}
