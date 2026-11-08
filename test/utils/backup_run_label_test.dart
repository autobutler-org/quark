import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/backup_run_label.dart';

/// A backup run is named by its folder, in the Quark's local time (#4032).
void main() {
  test('a run folder reads as its day and minute', () {
    expect(backupRunLabel('2026-11-02 09.00'), 'Nov 2, 09.00');
    expect(backupRunLabel('2026-01-15 21.57 (2)'), 'Jan 15, 21.57 (2)');
  });

  test('any other folder is shown as it is', () {
    expect(backupRunLabel('old layout'), 'old layout');
    expect(backupRunLabel('2026-13-02 09.00'), '2026-13-02 09.00');
  });

  test('a run item names its size and its drives', () {
    final item = backupRunItem(
      const BackupRun(
        folder: '2026-11-02 09.00',
        sizeBytes: 1536,
        drives: [
          (folder: 'Built-in storage', serial: '', name: ''),
          (folder: 'Photos (USB 90C82C65)', serial: '90C8', name: 'Photos'),
        ],
      ),
    );

    expect(item.id, '2026-11-02 09.00');
    expect(item.time, 'Nov 2, 09.00');
    expect(item.size, '1.5 KB');
    expect(item.drives, 'Built-in storage, Photos');
  });
}
