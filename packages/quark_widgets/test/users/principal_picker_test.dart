import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// Picking an account or a group (#1910, #1911). Worth guarding: keys that
/// tell an account from a group with the same id, a search that ignores case,
/// and a selection that is the caller's to hold.
void main() {
  const everyone = PrincipalItem(
    kind: PrincipalKind.group,
    id: 1,
    name: 'everyone',
    isBuiltin: true,
  );
  const family = PrincipalItem(
    kind: PrincipalKind.group,
    id: 2,
    name: 'Family',
  );
  const ada = PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada');
  const bob = PrincipalItem(kind: PrincipalKind.user, id: 2, name: 'bob');
  const options = [everyone, family, ada, bob];

  Finder option(PrincipalItem p) =>
      find.byKey(ValueKey('principal_option_${p.keySuffix}'));

  testBothViewports('lists every option under a key naming its kind', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      PrincipalPicker(options: options, onSelected: (_) {}),
      size: size,
    );

    expect(find.byKey(const ValueKey('principal_search')), findsOneWidget);
    for (final p in options) {
      expect(option(p), findsOneWidget, reason: '${p.keySuffix} is missing');
    }
    expect(find.text('Every account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('narrows the options as a name is typed, ignoring case', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      PrincipalPicker(options: options, onSelected: (_) {}),
      size: size,
    );

    await tester.enterText(
      find.byKey(const ValueKey('principal_search')),
      'FA',
    );
    await tester.pump();

    expect(option(family), findsOneWidget);
    for (final p in [everyone, ada, bob]) {
      expect(option(p), findsNothing, reason: '${p.name} should be hidden');
    }

    await tester.enterText(
      find.byKey(const ValueKey('principal_search')),
      'zed',
    );
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('says so when there is no one to pick', (tester) async {
    await pumpAt(
      tester,
      PrincipalPicker(options: const [], onSelected: (_) {}),
    );

    expect(find.text('No one to pick'), findsOneWidget);
  });

  testBothViewports('reports the option that was tapped', (tester, size) async {
    final picked = <PrincipalItem>[];
    await pumpAt(
      tester,
      PrincipalPicker(options: options, onSelected: picked.add),
      size: size,
    );

    await tester.tap(option(bob));
    await tester.tap(option(everyone));
    await tester.pump();

    expect(picked, [bob, everyone]);
  });

  testWidgets('marks only the option the caller says is selected', (
    tester,
  ) async {
    await pumpAt(
      tester,
      PrincipalPicker(options: options, selected: ada, onSelected: (_) {}),
    );

    expect(
      find.descendant(of: option(ada), matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
    // A group with the same id is not the same principal.
    expect(tester.widget<ListTile>(option(everyone)).selected, isFalse);
  });

  testBothViewports('survives long names and a long list', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      SingleChildScrollView(
        child: PrincipalPicker(
          options: [
            for (var i = 0; i < 100; i++)
              PrincipalItem(
                kind: i.isEven ? PrincipalKind.user : PrincipalKind.group,
                id: i,
                name: 'name $i ${'x' * 80}',
              ),
          ],
          onSelected: (_) {},
        ),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: colors come from the tokens', (tester) async {
      await pumpAt(
        tester,
        PrincipalPicker(options: options, selected: ada, onSelected: (_) {}),
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<ListTile>(option(ada)).selectedColor,
        tokens.primary,
      );
      expect(
        tester.widget<Text>(find.text('Every account')).style?.color,
        tokens.mutedForeground,
      );
    });
  }
}
