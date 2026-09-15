import 'package:flutter/material.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/router.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Gives every main page's top bar a [JobsBadge] counting [controller]'s
/// running jobs, through one [QuarkAppBarTrailing] scope at the app root.
class JobsBadgeHost extends StatelessWidget {
  /// Creates the scope around [child].
  const JobsBadgeHost({
    required this.controller,
    required this.onNavigate,
    required this.child,
    super.key,
  });

  /// Where the running count comes from.
  final JobsController controller;

  /// Opens a route. The root sits above the navigator, so the app passes the
  /// router's own `go` rather than a context lookup.
  final ValueChanged<String> onNavigate;

  /// The rest of the app.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return QuarkAppBarTrailing(
      actions: [
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => JobsBadge(
            runningCount: controller.runningCount,
            onTap: () => onNavigate(AppRoutes.jobs),
          ),
        ),
      ],
      child: child,
    );
  }
}
