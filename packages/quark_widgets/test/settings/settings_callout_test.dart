import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _key = ValueKey('settings_callout');

/// A settings block that stands on its own: a section heading over one card,
/// with a gap under the block (#4104).
void main() {
  testBothViewports('heading over one padded card, gap below', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      SettingsCallout(
        key: _key,
        title: 'Restart Quark',
        child: Text('Turn Quark off and back on. ' * 10),
      ),
      size: size,
    );

    expect(find.byKey(const ValueKey('section_restart_quark')), findsOneWidget);
    expect(find.text('Restart Quark'), findsOneWidget);
    final card = find.descendant(
      of: find.byKey(_key),
      matching: find.byType(Card),
    );
    expect(card, findsOneWidget);

    final text = find.textContaining('Turn Quark off');
    // The card's surface, inside the card's own margin.
    final cardRect = tester.getRect(
      find.descendant(of: card, matching: find.byType(Material)).first,
    );
    final textRect = tester.getRect(text);
    expect(textRect.left - cardRect.left, closeTo(16, 0.5));
    expect(textRect.top - cardRect.top, closeTo(16, 0.5));
    expect(
      tester.getBottomLeft(find.byKey(_key)).dy -
          tester.getBottomLeft(find.byType(QuarkSection)).dy,
      24,
    );
    expect(cardRect.right, lessThanOrEqualTo(size.width));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the child keeps its keys and callbacks', (tester) async {
    var taps = 0;
    await pumpAt(
      tester,
      SettingsCallout(
        title: 'Repair installation',
        child: FilledButton(
          key: const ValueKey('repair_installation_button'),
          onPressed: () => taps++,
          child: const Text('Repair installation'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('repair_installation_button')));
    expect(taps, 1);
  });
}
