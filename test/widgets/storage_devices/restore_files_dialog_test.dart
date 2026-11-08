import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/restore_files_dialog.dart';

typedef _Choice = ({bool toBuiltIn, String? run});

/// The restore confirm step: it warns that deleted files come back, names
/// the backup it restores and lets another be picked (#4032), and pops with
/// whether a gone drive's files go to built-in storage and the run.
void main() {
  /// Opens the dialog over [runs]; the returned list receives what it pops
  /// with.
  Future<List<_Choice?>> open(
    WidgetTester tester, {
    List<BackupRun> runs = const [],
  }) async {
    final popped = <_Choice?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped.add(
              await showDialog<_Choice>(
                context: context,
                builder: (_) => RestoreFilesDialog(runs: runs),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return popped;
  }

  testWidgets('warns that files deleted since come back', (tester) async {
    await open(tester);
    expect(find.textContaining('deleted since'), findsOneWidget);
  });

  testWidgets('confirm pops false by default', (tester) async {
    final popped = await open(tester);
    await tester.tap(find.byKey(const ValueKey('restore_files_confirm')));
    await tester.pumpAndSettle();
    expect(popped, [(toBuiltIn: false, run: null)]);
  });

  testWidgets('confirm pops true once built-in storage is chosen', (
    tester,
  ) async {
    final popped = await open(tester);
    await tester.tap(find.byKey(const ValueKey('restore_files_to_built_in')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('restore_files_confirm')));
    await tester.pumpAndSettle();
    expect(popped, [(toBuiltIn: true, run: null)]);
  });

  testWidgets('cancel pops nothing', (tester) async {
    final popped = await open(tester);
    await tester.tap(find.byKey(const ValueKey('restore_files_cancel')));
    await tester.pumpAndSettle();
    expect(popped, [null]);
  });

  testWidgets('names the newest backup, and sends the one picked', (
    tester,
  ) async {
    final popped = await open(
      tester,
      runs: const [
        BackupRun(folder: '2026-11-02 09.00', sizeBytes: 1024),
        BackupRun(folder: '2026-10-26 09.00', sizeBytes: 2048),
      ],
    );
    expect(find.text('From the backup of Nov 2, 09.00.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('backup_run_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oct 26, 09.00 · 2.0 KB').last);
    await tester.pumpAndSettle();
    expect(find.text('From the backup of Oct 26, 09.00.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('restore_files_confirm')));
    await tester.pumpAndSettle();
    expect(popped, [(toBuiltIn: false, run: '2026-10-26 09.00')]);
  });
}
