import 'package:flutter/material.dart';
import 'package:quark/models/app_notification.dart';

/// The words for each [NotificationType], in the one place the notification
/// list and the Settings switches both read them. The Quark sends a type and
/// no text, so the copy is the app's.
extension NotificationTypeCopy on NotificationType {
  /// The notification's headline in the list.
  String get title => switch (this) {
    NotificationType.backupDue => 'Back up this Quark',
    NotificationType.backupStale => 'Your backup is out of date',
  };

  /// The name of the type's switch in Settings.
  String get settingTitle => switch (this) {
    NotificationType.backupDue => 'No backup yet',
    NotificationType.backupStale => 'Backup out of date',
  };

  /// What the type's switch in Settings turns on.
  String get settingDescription => switch (this) {
    NotificationType.backupDue =>
      'Remind me while this Quark has never been backed up.',
    NotificationType.backupStale =>
      'Remind me when the last backup is getting old.',
  };
}

/// The words for one [AppNotification] in the notification list.
extension AppNotificationCopy on AppNotification {
  /// The sentence under the headline, with dates as [localizations] writes
  /// them.
  String body(MaterialLocalizations localizations) {
    final lastBackupAt = this.lastBackupAt;
    return switch (type) {
      NotificationType.backupDue =>
        'This Quark has never been backed up. Open Storage to start a backup.',
      NotificationType.backupStale when lastBackupAt != null =>
        'The last backup finished on '
            '${localizations.formatShortDate(lastBackupAt.toLocal())}. '
            'Open Storage to run another.',
      NotificationType.backupStale =>
        'The last backup is getting old. Open Storage to run another.',
    };
  }
}
