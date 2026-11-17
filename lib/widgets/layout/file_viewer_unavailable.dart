import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/layout/file_viewer_chrome.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The viewer for a file the Quark could not hand over: the viewer's chrome
/// around a sentence saying why, from [Errors], and a button back to where
/// the file was opened from (#3981).
///
/// A file whose drive was unplugged says so and asks for the drive back,
/// rather than the browser showing the Quark's raw JSON refusal.
///
/// Key prefixes: `file_viewer_unavailable_back`.
class FileViewerUnavailable extends StatelessWidget {
  /// Creates the error view for the file called [name], which failed with
  /// [error].
  const FileViewerUnavailable({
    required this.name,
    required this.error,
    required this.onClose,
    super.key,
  });

  /// The file name shown as the title.
  final String name;

  /// Why the file could not be opened. Turned into a sentence by [Errors].
  final Object? error;

  /// Leaves the viewer, from the back button and the "Go back" button.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => FileViewerChrome(
    name: name,
    onClose: onClose,
    body: EmptyStateWidget(
      icon: error is DriveNotConnected
          ? QuarkIcons.usb_outlined
          : QuarkIcons.error_outline,
      headline: Errors.message(error, 'open the file'),
      action: FilledButton(
        key: const ValueKey('file_viewer_unavailable_back'),
        onPressed: onClose,
        child: const Text('Go back'),
      ),
    ),
  );
}
