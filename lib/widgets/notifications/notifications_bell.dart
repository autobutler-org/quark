import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/widgets/notifications/notifications_list.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The app bar's notifications bell (#2493): a [QuarkBarIconButton] wearing
/// the count of [controller]'s notifications, which opens them in a
/// [NotificationsList] sheet when tapped.
///
/// Shown whenever someone is signed in, with or without notifications, so
/// the list and its empty state are always one tap away. Signed out it
/// renders nothing.
///
/// It sits in every main page's bar, below the navigator, so it opens the
/// sheet from its own context; the app root above the navigator only knows
/// how to [onNavigate].
///
/// Keys: `notifications_bell`, and those of [NotificationsList].
class NotificationsBell extends StatelessWidget {
  /// Creates the bell for [controller]'s notifications.
  const NotificationsBell({
    required this.controller,
    required this.onNavigate,
    super.key,
  });

  /// Where the notifications come from.
  final NotificationsController controller;

  /// Opens a route. The root passes the router's own `go`.
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isSignedIn) return const SizedBox.shrink();
        final count = controller.notifications.length;
        final tokens = QuarkTokens.of(context);
        return Badge(
          isLabelVisible: count > 0,
          label: Text(
            '$count',
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          backgroundColor: tokens.primary,
          textColor: tokens.primaryForeground,
          child: QuarkBarIconButton(
            key: const ValueKey('notifications_bell'),
            icon: QuarkIcons.notifications_outlined,
            tooltip: switch (count) {
              0 => 'Notifications',
              1 => '1 notification',
              _ => '$count notifications',
            },
            onPressed: () {
              // A backup goes stale with time alone, which no event
              // announces, so opening the list asks again.
              unawaited(controller.load());
              showQuarkSheet<void>(
                context,
                title: 'Notifications',
                builder: (sheetContext) => NotificationsList(
                  controller: controller,
                  onOpen: (notification) {
                    Navigator.of(sheetContext).pop();
                    onNavigate(notification.link);
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
