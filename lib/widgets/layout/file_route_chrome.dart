import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/router.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/widgets/layout/leave_pop_scope.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The scaffold of a viewer or editor opened at its own file URL (the code,
/// Markdown, plaintext and 3D model pages): the file name as the title, a
/// back button and the page's [actions]. The theme lives in Settings and,
/// on a phone, the account sheet (#4150).
///
/// Back pops when there is a page underneath and otherwise leaves the file
/// route through `AppRoutes.leaveFile`; a system back does the same through
/// [LeavePopScope], so a page opened by `context.go` never closes the app
/// (#2078).
class FileRouteChrome extends StatelessWidget {
  /// Creates the chrome around [body] for the file at [filePath].
  const FileRouteChrome({
    required this.filePath,
    required this.body,
    this.deviceSerial = '',
    this.dirty = false,
    this.actions = const [],
    super.key,
  });

  /// The file's files-relative path; its last segment is the title.
  final String filePath;

  /// The device the file is on, empty for the internal drive.
  final String deviceSerial;

  /// Marks the title with a dot for unsaved changes.
  final bool dirty;

  /// The page's own bar buttons.
  final List<Widget> actions;

  /// The page's content.
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final name = filePath.split('/').last;
    final canPop = context.canPop();
    void leave() => context.go(
      AppRoutes.leaveFile(context, filePath, serial: deviceSerial),
    );

    return LeavePopScope(
      onLeave: leave,
      child: Scaffold(
        appBar: ChromeAppBar(
          title: Text(dirty ? '$name •' : name),
          leading: BackButton(onPressed: canPop ? context.pop : leave),
          actions: [
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: QuarkTokens.of(context).spacingSm,
              children: actions,
            ),
          ],
        ),
        body: body,
      ),
    );
  }
}
