import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/app_notification.dart';

/// #2493: what `GET /notifications` sends, read into the app's model.
void main() {
  test('reads a backup_due entry, which has no lastBackupAt', () {
    final notification = AppNotification.tryFromJson({
      'type': 'backup_due',
      'link': '/system/storage',
    });
    expect(notification?.type, NotificationType.backupDue);
    expect(notification?.link, '/system/storage');
    expect(notification?.lastBackupAt, isNull);
  });

  test('reads a backup_stale entry with when the last backup finished', () {
    final notification = AppNotification.tryFromJson({
      'type': 'backup_stale',
      'link': '/system/storage',
      'lastBackupAt': '2026-09-01T10:00:00Z',
    });
    expect(notification?.type, NotificationType.backupStale);
    expect(notification?.lastBackupAt, DateTime.utc(2026, 9, 1, 10));
  });

  test('skips a type this app does not know', () {
    expect(
      AppNotification.tryFromJson({'type': 'calendar_reminder', 'link': '/x'}),
      isNull,
    );
  });

  test('skips an entry with no link, or that is not an object', () {
    expect(AppNotification.tryFromJson({'type': 'backup_due'}), isNull);
    expect(
      AppNotification.tryFromJson({'type': 'backup_due', 'link': ''}),
      isNull,
    );
    expect(AppNotification.tryFromJson('backup_due'), isNull);
  });

  test('every type round-trips through its wire name', () {
    for (final type in NotificationType.values) {
      expect(NotificationType.tryParse(type.wire), type);
    }
    expect(NotificationType.tryParse('nope'), isNull);
    expect(NotificationType.tryParse(null), isNull);
  });
}
