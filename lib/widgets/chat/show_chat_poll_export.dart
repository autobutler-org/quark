import 'package:flutter/material.dart';
import 'package:quark/utils/chat_poll_export.dart';

/// Asks how to export a poll's results (#3894): a format, and then where it
/// goes, Download or Save to Quark. One line says a copy saved to the Quark
/// is not end-to-end encrypted.
///
/// Null means nothing is exported: Cancel, or a tap outside the dialog.
/// Keys: `poll_export_dialog_format_<format>`, `poll_export_dialog_download`,
/// `poll_export_dialog_quark`, `poll_export_dialog_cancel`.
Future<(ChatPollExportFormat, ChatPollExportDestination)?> showChatPollExport(
  BuildContext context,
) {
  var format = ChatPollExportFormat.csv;
  return showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Export results'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<ChatPollExportFormat>(
              showSelectedIcon: false,
              segments: [
                for (final f in ChatPollExportFormat.values)
                  ButtonSegment(
                    value: f,
                    label: Text(
                      f.label,
                      key: ValueKey('poll_export_dialog_format_${f.name}'),
                    ),
                  ),
              ],
              selected: {format},
              onSelectionChanged: (picked) =>
                  setState(() => format = picked.single),
            ),
            const SizedBox(height: 16),
            const Text(
              'A copy saved to your Quark is not end-to-end encrypted.',
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('poll_export_dialog_cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          for (final (key, label, destination) in const [
            (
              'poll_export_dialog_quark',
              'Save to Quark',
              ChatPollExportDestination.quark,
            ),
            (
              'poll_export_dialog_download',
              'Download',
              ChatPollExportDestination.download,
            ),
          ])
            TextButton(
              key: ValueKey(key),
              onPressed: () => Navigator.of(context).pop((format, destination)),
              child: Text(label),
            ),
        ],
      ),
    ),
  );
}
