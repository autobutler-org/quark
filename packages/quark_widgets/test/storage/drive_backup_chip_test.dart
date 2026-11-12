import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// A data drive's backup chip: the label it was given, tinted by the level,
/// opening to one line per copy when there are copies.
void main() {
  testBothViewports('a drive with no copies is a plain label', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      DriveBackupChip(
        id: 'internal',
        level: DataProtectionLevel.unprotected,
        label: 'Not backed up',
        expanded: false,
        onExpandedChanged: (_) {},
      ),
      size: size,
    );

    expect(find.text('Not backed up'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(
      find.byKey(const ValueKey('drive_backup_chip_internal')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('opens to one line per copy', (tester, size) async {
    await pumpAt(
      tester,
      DriveBackupChip(
        id: 'usb-1',
        level: DataProtectionLevel.basic,
        label: 'Backed up Nov 2 · Backup A ' * 6,
        copies: [
          'Backup A · Nov 2',
          'Office · Sep 1 · This copy is more than 30 days old. ' * 4,
        ],
        expanded: true,
        onExpandedChanged: (_) {},
      ),
      size: size,
    );

    expect(find.text('Backup A · Nov 2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('drive_backup_copy_usb-1_1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap reports the next open state', (tester) async {
    final changes = <bool>[];
    await pumpAt(
      tester,
      DriveBackupChip(
        id: 'usb-1',
        level: DataProtectionLevel.protected,
        label: 'Protected · Nov 2',
        copies: const ['Backup A · Nov 2', 'Backup B · Nov 1'],
        expanded: false,
        onExpandedChanged: changes.add,
      ),
    );

    expect(find.text('Backup A · Nov 2'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('drive_backup_chip_usb-1')));
    await tester.pump();

    expect(changes, [true]);
  });

  testWidgets('the tint follows the level', (tester) async {
    await pumpAt(
      tester,
      DriveBackupChip(
        id: 'usb-1',
        level: DataProtectionLevel.protected,
        label: 'Protected · Nov 2',
        expanded: false,
        onExpandedChanged: (_) {},
      ),
    );

    expect(
      tester.widget<QuarkTintBadge>(find.byType(QuarkTintBadge)).color,
      QuarkTokens.dark.success,
    );
  });
}
