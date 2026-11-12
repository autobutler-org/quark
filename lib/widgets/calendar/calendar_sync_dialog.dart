import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/calendar_controller.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/clipboard_utils.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Connects the calendar to other calendar apps (#1151): the subscription
/// link Apple Calendar, Google Calendar or Thunderbird polls, with a copy
/// button, a one-time download of the calendar as an .ics file for an app
/// that cannot reach the Quark, and an import of an .ics file another app
/// exported.
///
/// App-side because it reads [calendar], the clipboard, the file picker and
/// the platform's save dialog. A successful import closes the dialog and
/// says how many events came in.
///
/// Keys: `calendar_subscription_copy`, `calendar_download_ics`,
/// `calendar_import_ics`, and `calendar_sync_close`.
class CalendarSyncDialog extends StatefulWidget {
  /// Creates the dialog over [calendar].
  const CalendarSyncDialog({required this.calendar, super.key});

  /// Loads the link and imports the file.
  final CalendarController calendar;

  @override
  State<CalendarSyncDialog> createState() => _CalendarSyncDialogState();
}

class _CalendarSyncDialogState extends State<CalendarSyncDialog> {
  late final Future<String> _url = widget.calendar.subscriptionUrl();
  bool _importing = false;
  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final bytes = await widget.calendar.downloadICal();
      final saved = await FilesService.saveBytesToFile(bytes, 'quark.ics');
      if (saved != null && mounted) showMessage(context, 'Saved quark.ics');
    } catch (e) {
      if (mounted) {
        showMessage(context, Errors.message(e, 'download the calendar'));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['ics'],
    );
    if (file == null || !mounted) return;
    setState(() => _importing = true);
    try {
      final result = await widget.calendar.importICal(await file.readAsBytes());
      if (!mounted) return;
      final events = result.imported == 1 ? 'event' : 'events';
      showMessage(
        context,
        'Imported ${result.imported} $events'
        '${result.skipped > 0 ? ', ${result.skipped} skipped' : ''}',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showMessage(context, Errors.message(e, 'import the calendar'));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final heading = Theme.of(context).textTheme.titleSmall;
    return AlertDialog(
      scrollable: true,
      title: const Text('Sync with other calendar apps'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Subscribe', style: heading),
          SizedBox(height: tokens.spacingSm),
          const Text(
            'Paste this link into Apple Calendar (File › New Calendar '
            'Subscription) or Thunderbird on a device that can reach your '
            'Quark. Google Calendar (Other calendars › From URL) fetches it '
            'from Google\'s servers, so it needs remote access turned on. '
            'The link carries your sign-in, so share it with no one.',
          ),
          SizedBox(height: tokens.spacingSm),
          FutureBuilder<String>(
            future: _url,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  Errors.message(snapshot.error!, 'load the subscription link'),
                  style: TextStyle(color: tokens.error),
                );
              }
              final url = snapshot.data;
              if (url == null) {
                return const Align(child: QuarkLoader(size: 20));
              }
              return Row(
                children: [
                  Expanded(child: SelectableText(url)),
                  CopyButton(
                    key: const ValueKey('calendar_subscription_copy'),
                    text: url,
                    onCopy: (text) => copyToClipboard(context, text),
                    unavailableReason: clipboardUnavailableReason,
                  ),
                ],
              );
            },
          ),
          SizedBox(height: tokens.spacingLg),
          Text('Download', style: heading),
          SizedBox(height: tokens.spacingSm),
          const Text(
            'Or save the calendar once as an .ics file and import it '
            'anywhere, Google Calendar included. It will not pick up later '
            'changes.',
          ),
          SizedBox(height: tokens.spacingSm),
          OutlinedButton(
            key: const ValueKey('calendar_download_ics'),
            onPressed: _downloading ? null : _download,
            child: _downloading
                ? const QuarkLoader(size: 20)
                : const Text('Download .ics file'),
          ),
          SizedBox(height: tokens.spacingLg),
          Text('Import', style: heading),
          SizedBox(height: tokens.spacingSm),
          const Text(
            'Add the events from an .ics file exported by another calendar '
            'app. Events already on the calendar are left alone.',
          ),
          SizedBox(height: tokens.spacingSm),
          FilledButton(
            key: const ValueKey('calendar_import_ics'),
            onPressed: _importing ? null : _import,
            child: _importing
                ? const QuarkLoader(size: 20)
                : const Text('Import .ics file'),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('calendar_sync_close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
