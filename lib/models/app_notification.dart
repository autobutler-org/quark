import 'package:flutter/foundation.dart';

/// A kind of notification, named as the Quark names it. It is what
/// `GET /notifications` sends and what an account's `disabledNotifications`
/// setting lists to turn one off.
enum NotificationType {
  /// This Quark has no completed snapshot backup on record.
  backupDue('backup_due'),

  /// The last completed snapshot backup is old enough to be stale.
  backupStale('backup_stale');

  const NotificationType(this.wire);

  /// The type as the API spells it.
  final String wire;

  /// The type the API spells [wire], or null for one this app does not know,
  /// such as a type a newer Quark added.
  static NotificationType? tryParse(Object? wire) {
    for (final type in values) {
      if (type.wire == wire) return type;
    }
    return null;
  }
}

/// One thing the Quark has to tell this account, from
/// `GET /api/v0/notifications`. It carries no title or body: the app writes
/// the copy from [type].
@immutable
class AppNotification {
  /// Creates a notification.
  const AppNotification({
    required this.type,
    required this.link,
    this.lastBackupAt,
  });

  /// What kind of notification this is.
  final NotificationType type;

  /// The app route to open when the notification is tapped.
  final String link;

  /// When the last snapshot backup completed. Only
  /// [NotificationType.backupStale] carries it.
  final DateTime? lastBackupAt;

  /// The notification in [json], or null when its type is one this app does
  /// not know or it has no link, so a newer Quark's entry is skipped rather
  /// than breaking the list.
  static AppNotification? tryFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final type = NotificationType.tryParse(json['type']);
    final link = json['link'];
    final lastBackupAt = json['lastBackupAt'];
    if (type == null || link is! String || link.isEmpty) return null;
    return AppNotification(
      type: type,
      link: link,
      lastBackupAt: lastBackupAt is String
          ? DateTime.tryParse(lastBackupAt)
          : null,
    );
  }
}
