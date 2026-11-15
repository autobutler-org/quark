import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The scaffold of a viewer pushed over another page (the audio, video, PDF,
/// SVG and fallback viewers): the file [name] as the title, the page's
/// [actions] and the theme toggle.
///
/// With [onClose] the back button calls it; without, the app bar's own back
/// button pops the route the viewer was pushed on.
class FileViewerChrome extends StatelessWidget {
  /// Creates the chrome around [body] for the file called [name].
  const FileViewerChrome({
    required this.name,
    required this.body,
    this.onClose,
    this.actions = const [],
    super.key,
  });

  /// The file name shown as the title.
  final String name;

  /// Closes the viewer from its back button. Null leaves the app bar's own.
  final VoidCallback? onClose;

  /// The page's own bar buttons, placed before the theme toggle.
  final List<Widget> actions;

  /// The page's content.
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final onClose = this.onClose;
    return Scaffold(
      appBar: ChromeAppBar(
        leading: onClose == null ? null : BackButton(onPressed: onClose),
        title: Text(name),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: QuarkTokens.of(context).spacingSm,
            children: [...actions, const AppThemeToggle()],
          ),
        ],
      ),
      body: body,
    );
  }
}
