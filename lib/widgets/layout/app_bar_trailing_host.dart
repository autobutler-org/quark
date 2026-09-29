import 'package:flutter/material.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/router.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Gives every main page's top bar the app-wide controls, through one
/// [QuarkAppBarTrailing] scope at the app root: a [ConnectionIndicator] fed
/// by [connection] (#1880) and a [JobsBadge] counting [jobs]' running jobs.
///
/// The indicator is left out until [connection] has a mode, which is never on
/// web and never with no Quark configured.
class AppBarTrailingHost extends StatelessWidget {
  /// Creates the scope around [child].
  const AppBarTrailingHost({
    required this.jobs,
    required this.connection,
    required this.onNavigate,
    required this.child,
    super.key,
  });

  /// Where the running count comes from.
  final JobsController jobs;

  /// Where the local, remote or offline state comes from.
  final ConnectionController connection;

  /// Opens a route. The root sits above the navigator, so the app passes the
  /// router's own `go` rather than a context lookup.
  final ValueChanged<String> onNavigate;

  /// The rest of the app.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final mode = connection.mode;
        return QuarkAppBarTrailing(
          actions: [
            if (mode != null)
              ConnectionIndicator(
                mode: mode,
                label: switch (mode) {
                  ConnectionMode.local => 'Connected on your home network',
                  ConnectionMode.remote => 'Connected through remote access',
                  ConnectionMode.offline => 'Your Quark is not reachable',
                },
              ),
            ListenableBuilder(
              listenable: jobs,
              builder: (context, _) => JobsBadge(
                runningCount: jobs.runningCount,
                onTap: () => onNavigate(AppRoutes.systemTab(SystemTab.jobs)),
              ),
            ),
          ],
          child: child,
        );
      },
    );
  }
}
