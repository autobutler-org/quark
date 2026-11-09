import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _runs = [
  BackupRunItem(id: '2026-11-02 09.00', time: 'Nov 2, 09.00', size: '1.2 GB'),
  BackupRunItem(id: '2026-10-26 09.00', time: 'Oct 26, 09.00', size: '1.1 GB'),
];

/// The run a restore reads: named in a sentence, with a menu to pick another
/// when the drive holds more than one.
void main() {
  testBothViewports('names the selected run and offers the others', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      BackupRunPicker(
        runs: _runs,
        selected: '2026-11-02 09.00',
        onSelected: (_) {},
      ),
      size: size,
    );

    expect(find.text('From the backup of Nov 2, 09.00.'), findsOneWidget);
    expect(find.byKey(const ValueKey('backup_run_picker')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('one run is the sentence alone', (tester, size) async {
    await pumpAt(
      tester,
      BackupRunPicker(
        runs: _runs.sublist(0, 1),
        selected: '2026-11-02 09.00',
        onSelected: (_) {},
      ),
      size: size,
    );

    expect(find.text('From the backup of Nov 2, 09.00.'), findsOneWidget);
    expect(find.byKey(const ValueKey('backup_run_picker')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking another run reports it', (tester) async {
    final picked = <String>[];
    await pumpAt(
      tester,
      BackupRunPicker(
        runs: _runs,
        selected: '2026-11-02 09.00',
        onSelected: picked.add,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('backup_run_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oct 26, 09.00 · 1.1 GB').last);
    await tester.pumpAndSettle();

    expect(picked, ['2026-10-26 09.00']);
  });
}
