import 'package:flutter/material.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/models/app_notification.dart';
import 'package:quark/widgets/notifications/notification_copy.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The account's notifications, as the sheet behind the app bar's bell shows
/// them (#2493): one row per notification, each opening the page that deals
/// with it.
///
/// Rebuilds as [controller] changes. Until the first answer it shows a
/// loader, or the failure with a way to try again. After that the rows stay
/// up while a refresh runs, and a list that came back empty says so.
///
/// Keys: `notification_tile_<type>` on each row, where `<type>` is the
/// type as the API spells it (`notification_tile_backup_due`), and
/// `notifications_retry`.
class NotificationsList extends StatelessWidget {
  /// Creates the list of [controller]'s notifications.
  const NotificationsList({
    required this.controller,
    required this.onOpen,
    super.key,
  });

  /// Where the notifications come from.
  final NotificationsController controller;

  /// Called with the notification the user tapped, to close the sheet and
  /// open its link.
  final ValueChanged<AppNotification> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tokens = QuarkTokens.of(context);
        final notifications = controller.notifications;
        final error = controller.error;
        if (!controller.hasLoaded) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: tokens.spacingLg),
            child: error == null
                ? const Center(child: QuarkLoader())
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error, textAlign: TextAlign.center),
                      SizedBox(height: tokens.spacingMd),
                      OutlinedButton(
                        key: const ValueKey('notifications_retry'),
                        onPressed: controller.load,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
          );
        }
        if (notifications.isEmpty) {
          return const EmptyStateWidget(
            icon: QuarkIcons.notifications_outlined,
            headline: "You're all caught up",
            subtext: 'Reminders from this Quark show up here.',
          );
        }
        final localizations = MaterialLocalizations.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final notification in notifications)
              ListTile(
                key: ValueKey('notification_tile_${notification.type.wire}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(QuarkIcons.backup_outlined),
                title: Text(notification.type.title),
                subtitle: Text(notification.body(localizations)),
                trailing: const Icon(QuarkIcons.chevron_right),
                onTap: () => onOpen(notification),
              ),
          ],
        );
      },
    );
  }
}
