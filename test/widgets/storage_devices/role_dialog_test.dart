import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/storage_devices/role_dialog.dart';

/// #3194, #3999: the roles Set Role offers. Built-in storage can be a backup
/// drive, so an external drive's files have somewhere to land.
void main() {
  Future<List<String?>> pumpDialog(
    WidgetTester tester, {
    required bool isInternal,
  }) async {
    final popped = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped.add(
              await showDialog<String>(
                context: context,
                builder: (_) => RoleDialog(
                  currentRole: 'unassigned',
                  isInternal: isInternal,
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

  testWidgets('a USB drive is offered every role', (tester) async {
    await pumpDialog(tester, isInternal: false);

    for (final role in ['Default Storage', 'Backup drive', 'Unassigned']) {
      expect(find.text(role), findsOneWidget);
    }
    expect(find.textContaining('also copied onto it'), findsOneWidget);
    expect(
      find.text(
        'Your other drives are copied onto it when you back up. Keep it '
        'somewhere safe between backups.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('built-in storage can be a backup drive', (tester) async {
    final popped = await pumpDialog(tester, isInternal: true);

    expect(find.text('Backup drive'), findsOneWidget);
    expect(find.text('Other drives are backed up onto it'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.textContaining('also copied onto it'), findsNothing);

    await tester.tap(find.text('Backup drive'));
    await tester.pumpAndSettle();

    expect(popped, ['snapshot-backup']);
  });
}
