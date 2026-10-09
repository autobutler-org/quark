import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/models/app_notification.dart';
import 'package:quark/widgets/notifications/notification_copy.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Settings control for which notifications the account receives
/// (#2493): a heading over one switch per [NotificationType], on while the
/// type is delivered.
///
/// It asks [controller] to read the account's choices when it first shows.
/// Until they arrive it shows a loader, or the failure with a way to try
/// again. A switch flips at once and flips back, with the reason under the
/// switches, if the Quark refuses the save. The switches are disabled while a
/// save is in flight.
///
/// Keys: `notification_toggle_<type>` on each switch, where `<type>` is
/// the type as the API spells it (`notification_toggle_backup_due`), and
/// `notification_preferences_retry`.
class NotificationPreferencesCard extends StatefulWidget {
  /// Creates the control for [controller]'s account.
  const NotificationPreferencesCard({required this.controller, super.key});

  /// Where the choices are read from and saved through.
  final NotificationsController controller;

  @override
  State<NotificationPreferencesCard> createState() =>
      _NotificationPreferencesCardState();
}

class _NotificationPreferencesCardState
    extends State<NotificationPreferencesCard> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.loadPreferences());
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final error = controller.preferencesError;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notifications',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (controller.preferencesLoaded)
              Card(
                child: Column(
                  children: [
                    for (final type in NotificationType.values)
                      SwitchListTile(
                        key: ValueKey('notification_toggle_${type.wire}'),
                        title: Text(type.settingTitle),
                        subtitle: Text(type.settingDescription),
                        value: controller.isEnabled(type),
                        onChanged: controller.isSaving
                            ? null
                            : (enabled) => controller.setEnabled(type, enabled),
                      ),
                  ],
                ),
              )
            else if (error == null)
              const Center(child: QuarkLoader(size: 20)),
            if (error != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
              if (!controller.preferencesLoaded)
                TextButton(
                  key: const ValueKey('notification_preferences_retry'),
                  onPressed: controller.loadPreferences,
                  child: const Text('Try again'),
                ),
            ],
          ],
        );
      },
    );
  }
}
