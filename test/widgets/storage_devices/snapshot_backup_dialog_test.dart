import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/storage_devices/snapshot_backup_dialog.dart';

/// #3984: a backup copies the data drives the admin leaves checked, every one
/// of them unless one is unchecked.
void main() {
  /// Opens the dialog over built-in storage and Photos and returns what it
  /// pops, filled in once it closes.
  Future<List<List<String>?>> pumpDialog(WidgetTester tester) async {
    final popped = <List<String>?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped.add(
              await showDialog<List<String>>(
                context: context,
                builder: (_) => const SnapshotBackupDialog(
                  targetName: 'Backups',
                  sources: {'': 'Built-in storage', 'USB3': 'Photos'},
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

  Finder start() => find.byKey(const ValueKey('snapshot_backup_start'));

  testWidgets('every data drive starts checked', (tester) async {
    final popped = await pumpDialog(tester);

    expect(find.text('Choose the drives to copy onto Backups.'), findsOne);
    expect(checked(tester, ''), isTrue);
    expect(checked(tester, 'USB3'), isTrue);

    await tester.tap(start());
    await tester.pumpAndSettle();

    expect(popped, [
      ['', 'USB3'],
    ]);
  });

  testWidgets('unchecking a drive leaves it out', (tester) async {
    final popped = await pumpDialog(tester);

    await tester.tap(find.byKey(const ValueKey('backup_source_USB3')));
    await tester.pump();
    await tester.tap(start());
    await tester.pumpAndSettle();

    expect(popped, [
      [''],
    ]);
  });

  testWidgets('with no drive checked there is nothing to start', (
    tester,
  ) async {
    await pumpDialog(tester);

    await tester.tap(find.byKey(const ValueKey('backup_source_')));
    await tester.tap(find.byKey(const ValueKey('backup_source_USB3')));
    await tester.pump();

    expect(tester.widget<TextButton>(start()).onPressed, isNull);
  });

  testWidgets('Cancel pops nothing', (tester) async {
    final popped = await pumpDialog(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(popped, [null]);
  });
}
