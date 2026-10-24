import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _full = VaultEntryDraft(
  name: 'GitHub',
  url: 'https://github.com',
  username: 'grace',
  password: 'hunter22',
  notes: 'Codes in the safe.',
  totpSecret: 'JBSWY3DPEHPK3PXP',
);

void main() {
  VaultEntryDetails details({
    VaultEntryDraft entry = _full,
    bool showPassword = false,
    String folderName = 'Work',
    List<String>? log,
  }) => VaultEntryDetails(
    entry: entry,
    folderName: folderName,
    showPassword: showPassword,
    onToggleShowPassword: () => log?.add('toggle'),
    onCopy: (label, value) => log?.add('$label=$value'),
  );

  testBothViewports('shows every field but the masked password and the '
      'two-factor seed', (tester, size) async {
    await pumpAt(tester, details(), size: size);

    expect(find.text('grace'), findsOneWidget);
    expect(find.text('hunter22'), findsNothing);
    expect(find.text('••••••••'), findsOneWidget);
    expect(find.text('https://github.com'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('JBSWY3DPEHPK3PXP'), findsNothing);
    expect(find.text('Set up'), findsOneWidget);
    expect(find.text('Codes in the safe.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    await pumpAt(tester, Center(child: details()), size: size);

    await expectTapTargetGuidelines(tester);
  });

  testWidgets('shows the password when asked', (tester) async {
    await pumpAt(tester, details(showPassword: true));

    expect(find.text('hunter22'), findsOneWidget);
  });

  testWidgets('leaves out empty optional fields', (tester) async {
    await pumpAt(
      tester,
      details(
        entry: const VaultEntryDraft(name: 'Bare', password: 'x'),
        folderName: '',
      ),
    );

    expect(find.text('Website'), findsNothing);
    expect(find.text('Folder'), findsNothing);
    expect(find.text('Two-factor'), findsNothing);
    expect(find.text('Notes'), findsNothing);
    expect(find.byKey(const ValueKey('vault_detail_copy_url')), findsNothing);
  });

  testWidgets('reports copies and the reveal', (tester) async {
    final log = <String>[];
    await pumpAt(tester, details(log: log));

    await tester.tap(find.byKey(const ValueKey('vault_detail_copy_username')));
    await tester.tap(find.byKey(const ValueKey('vault_detail_copy_password')));
    await tester.tap(find.byKey(const ValueKey('vault_detail_copy_url')));
    await tester.tap(find.byKey(const ValueKey('vault_detail_reveal')));
    await tester.pump();

    expect(log, [
      'Username=grace',
      'Password=hunter22',
      'Website=https://github.com',
      'toggle',
    ]);
  });
}
