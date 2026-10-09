import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// A menu row opening a submenu on a click or a tap, never by hover alone
/// (#2898).
void main() {
  late List<String> events;

  Finder key(String k) => find.byKey(ValueKey(k));

  /// Pumps a menu of two submenus, Shape and Image, and opens it.
  Future<void> pumpMenu(WidgetTester tester, Size size) async {
    events = [];
    QuarkSubmenuButton submenu(String name, List<String> items) =>
        QuarkSubmenuButton(
          key: ValueKey(name),
          menuChildren: [
            for (final item in items)
              MenuItemButton(
                key: ValueKey(item),
                onPressed: () => events.add(item),
                child: Text(item),
              ),
          ],
          child: Text(name),
        );
    await pumpAt(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: MenuAnchor(
          menuChildren: [
            submenu('shape', ['star', 'oval']),
            submenu('image', ['device', 'quark']),
          ],
          builder: (context, menu, _) => TextButton(
            key: const ValueKey('insert'),
            onPressed: menu.open,
            child: const Text('Insert'),
          ),
        ),
      ),
      size: size,
    );
    await tester.tap(key('insert'));
    await tester.pumpAndSettle();
  }

  testBothViewports('a tap opens the submenu and a pick closes the menus', (
    tester,
    size,
  ) async {
    await pumpMenu(tester, size);
    expect(key('star'), findsNothing);
    await tester.tap(key('shape'));
    await tester.pumpAndSettle();
    expect(key('star'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(key('star'));
    await tester.pumpAndSettle();
    expect(events, ['star']);
    expect(key('shape'), findsNothing, reason: 'the whole menu closes');
  });

  testBothViewports('a click after the mouse rests on the row keeps it open', (
    tester,
    size,
  ) async {
    await pumpMenu(tester, size);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(key('shape')));
    await tester.pumpAndSettle();
    expect(
      key('star'),
      findsNothing,
      reason: 'resting there opens nothing the click could land on',
    );

    await mouse.down(tester.getCenter(key('shape')));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(key('star'), findsOneWidget);
  });

  testBothViewports('opening one submenu closes its sibling', (
    tester,
    size,
  ) async {
    await pumpMenu(tester, size);
    await tester.tap(key('shape'));
    await tester.pumpAndSettle();
    await tester.tap(key('image'));
    await tester.pumpAndSettle();
    expect(key('device'), findsOneWidget);
    expect(key('star'), findsNothing);
  });

  testWidgets('says whether it is expanded, and Escape closes it', (
    tester,
  ) async {
    await pumpMenu(tester, wideViewport);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('shape')),
      isSemantics(isExpanded: false, hasExpandedState: true),
    );
    await tester.tap(key('shape'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('shape')),
      isSemantics(isExpanded: true, hasExpandedState: true),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(key('star'), findsNothing);
    handle.dispose();
  });
}
