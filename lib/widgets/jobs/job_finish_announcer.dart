import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/controllers/jobs_controller.dart';

/// Shows a snack bar whenever [controller] announces a finished job, on
/// whatever page is open. Sits at the root of the app for the whole session.
class JobFinishAnnouncer extends StatefulWidget {
  /// Creates the announcer around [child].
  const JobFinishAnnouncer({
    required this.controller,
    required this.messengerKey,
    required this.onNavigate,
    required this.child,
    super.key,
  });

  /// Where announcements come from.
  final JobsController controller;

  /// The app's root messenger, so the snack bar survives page changes.
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  /// Opens a route when the snack bar's action is tapped.
  final ValueChanged<String> onNavigate;

  /// The rest of the app.
  final Widget child;

  @override
  State<JobFinishAnnouncer> createState() => _JobFinishAnnouncerState();
}

class _JobFinishAnnouncerState extends State<JobFinishAnnouncer> {
  late final StreamSubscription<JobAnnouncement> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.controller.announcements.listen(_show);
  }

  void _show(JobAnnouncement announcement) {
    final route = announcement.route;
    widget.messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(announcement.message),
        action: route == null
            ? null
            : SnackBarAction(
                label: announcement.actionLabel ?? '',
                onPressed: () => widget.onNavigate(route),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
