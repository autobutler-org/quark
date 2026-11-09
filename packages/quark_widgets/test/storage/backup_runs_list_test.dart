import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _runs = [
  BackupRunItem(
    id: '2026-11-02 09.00',
    time: 'Nov 2, 09.00',
    size: '1.2 GB',
    drives: 'Built-in storage, Photos',
  ),
  BackupRunItem(
    id: '2026-10-26 09.00',
    time: 'Oct 26, 09.00',
    size: '1.1 GB',
    drives: 'Built-in storage',
  ),
];

/// A backup drive's runs: a summary that opens to one row per run, each with
/// its time, size, drives and a delete action.
void main() {
  testBothViewports('collapsed shows the summary alone', (tester, size) async {
    await pumpAt(
      tester,
      BackupRunsList(
        id: 'USB2',
        summary: '2 backups · newest Nov 2',
        runs: _runs,
        expanded: false,
        onExpandedChanged: (_) {},
        onDelete: (_) {},
      ),
      size: size,
    );

    expect(find.text('2 backups · newest Nov 2'), findsOneWidget);
    expect(find.text('Nov 2, 09.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('expanded shows each run with its delete action', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      BackupRunsList(
        id: 'USB2',
        summary: '2 backups · newest Nov 2',
        runs: [
          ..._runs,
          BackupRunItem(
            id: 'long',
            time: 'Sep 1, 09.00',
            size: '900 MB',
            drives: 'A drive with a very long name, ' * 6,
          ),
        ],
        expanded: true,
        onExpandedChanged: (_) {},
        onDelete: (_) {},
      ),
      size: size,
    );

    expect(find.text('Nov 2, 09.00'), findsOneWidget);
    expect(find.text('1.2 GB · Built-in storage, Photos'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('backup_run_delete_USB2_1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('an error replaces the runs', (tester, size) async {
    await pumpAt(
      tester,
      BackupRunsList(
        id: 'USB2',
        summary: '2 backups · newest Nov 2',
        runs: _runs,
        expanded: true,
        error: "Couldn't list the backups.",
        onExpandedChanged: (_) {},
      ),
      size: size,
    );

    expect(find.text("Couldn't list the backups."), findsOneWidget);
    expect(find.text('Nov 2, 09.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading with no runs draws a loader', (tester) async {
    await pumpAt(
      tester,
      BackupRunsList(
        id: 'USB2',
        summary: '',
        runs: const [],
        expanded: false,
        isLoading: true,
        onExpandedChanged: (_) {},
      ),
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
  });

  testWidgets('no runs is a plain line with no toggle', (tester) async {
    await pumpAt(
      tester,
      BackupRunsList(
        id: 'USB2',
        summary: 'No backups yet',
        runs: const [],
        expanded: false,
        onExpandedChanged: (_) {},
      ),
    );

    expect(find.text('No backups yet'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('a tap opens it, and delete reports the run', (tester) async {
    final changes = <bool>[];
    final deleted = <String>[];
    await pumpAt(
      tester,
      BackupRunsList(
        id: 'USB2',
        summary: '2 backups · newest Nov 2',
        runs: _runs,
        expanded: true,
        onExpandedChanged: changes.add,
        onDelete: deleted.add,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('backup_runs_USB2')));
    await tester.tap(find.byKey(const ValueKey('backup_run_delete_USB2_1')));
    await tester.pump();

    expect(changes, [false]);
    expect(deleted, ['2026-10-26 09.00']);
  });

  testWidgets('no onDelete draws no delete action', (tester) async {
    await pumpAt(
      tester,
      BackupRunsList(
        id: 'USB2',
        summary: '2 backups · newest Nov 2',
        runs: _runs,
        expanded: true,
        onExpandedChanged: (_) {},
      ),
    );

    expect(find.byType(IconButton), findsNothing);
  });
}
