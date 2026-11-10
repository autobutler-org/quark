import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/backup_schedule_dialog.dart';

/// What the dialog pops.
typedef Choice = ({BackupCadence cadence, List<String> sourceSerials});

/// #3984: a backup drive's schedule is a cadence and the data drives it
/// copies. Every drive checked saves none, which is every data drive.
void main() {
  /// Opens the dialog over built-in storage and Photos and returns what it
  /// pops, filled in once it closes.
  Future<List<Choice?>> pumpDialog(
    WidgetTester tester, {
    BackupCadence cadence = BackupCadence.off,
    List<String> sourceSerials = const [],
  }) async {
    final popped = <Choice?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped.add(
              await showDialog<Choice>(
                context: context,
                builder: (_) => BackupScheduleDialog(
                  targetName: 'Backups',
                  sources: const {'': 'Built-in storage', 'USB3': 'Photos'},
                  cadence: cadence,
                  sourceSerials: sourceSerials,
                ),
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

  bool checked(WidgetTester tester, String serial) => tester
      .widget<CheckboxListTile>(find.byKey(ValueKey('backup_source_$serial')))
      .value!;

  Finder save() => find.byKey(const ValueKey('backup_schedule_save'));

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(save());
    await tester.pumpAndSettle();
  }

  testWidgets('a new schedule is off and copies every data drive', (
    tester,
  ) async {
    final popped = await pumpDialog(tester);

    expect(checked(tester, ''), isTrue);
    expect(checked(tester, 'USB3'), isTrue);
    await tapSave(tester);

    expect(popped.single?.cadence, BackupCadence.off);
    expect(popped.single?.sourceSerials, isEmpty);
  });

  testWidgets('choosing a cadence saves it', (tester) async {
    final popped = await pumpDialog(tester);

    await tester.tap(
      find.byKey(const ValueKey('backup_schedule_cadence_weekly')),
    );
    await tester.pump();
    await tapSave(tester);

    expect(popped.single?.cadence, BackupCadence.weekly);
    expect(popped.single?.sourceSerials, isEmpty);
  });

  testWidgets('unchecking a drive saves the ones left checked', (tester) async {
    final popped = await pumpDialog(tester, cadence: BackupCadence.daily);

    await tester.tap(find.byKey(const ValueKey('backup_source_USB3')));
    await tester.pump();
    await tapSave(tester);

    expect(popped.single?.cadence, BackupCadence.daily);
    expect(popped.single?.sourceSerials, ['']);
  });

  testWidgets('a saved schedule opens with its drives checked', (tester) async {
    final popped = await pumpDialog(
      tester,
      cadence: BackupCadence.monthly,
      sourceSerials: ['USB3'],
    );

    expect(checked(tester, ''), isFalse);
    expect(checked(tester, 'USB3'), isTrue);
    // Checking the last one is every drive again, which saves none.
    await tester.tap(find.byKey(const ValueKey('backup_source_')));
    await tester.pump();
    await tapSave(tester);

    expect(popped.single?.cadence, BackupCadence.monthly);
    expect(popped.single?.sourceSerials, isEmpty);
  });

  testWidgets('with no drive checked there is nothing to save', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.byKey(const ValueKey('backup_source_')));
    await tester.tap(find.byKey(const ValueKey('backup_source_USB3')));
    await tester.pump();

    expect(tester.widget<TextButton>(save()).onPressed, isNull);
  });

  testWidgets('Cancel pops nothing', (tester) async {
    final popped = await pumpDialog(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(popped, [null]);
  });
}
