import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The one bar button that opens a menu (#4103): an icon button or a chip
/// toggling a `MenuAnchor`.
void main() {
  const buttonKey = ValueKey('thing_menu');
  const itemKey = ValueKey('thing_menu_item');

  Widget menu({
    String? label,
    bool? selected,
    bool enabled = true,
    bool isBusy = false,
    VoidCallback? onItem,
  }) => Align(
    alignment: Alignment.topLeft,
    child: QuarkBarMenuButton(
      buttonKey: buttonKey,
      icon: QuarkIcons.download_outlined,
      tooltip: 'Thing menu',
      label: label,
      selected: selected,
      enabled: enabled,
      isBusy: isBusy,
      keepLabel: true,
      menuChildren: [
        MenuItemButton(
          key: itemKey,
          onPressed: onItem ?? () {},
          child: const Text('Do the thing'),
        ),
      ],
    ),
  );

  testBothViewports('an icon button opens and closes its menu', (
    tester,
    size,
  ) async {
    await pumpAt(tester, menu(), size: size);
    expect(tester.widget(find.byKey(buttonKey)), isA<QuarkBarIconButton>());
    expect(find.byKey(itemKey), findsNothing);

    await tester.tap(find.byKey(buttonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(itemKey), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(buttonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(itemKey), findsNothing);
  });

  testBothViewports('a label makes a chip whose menu meets its edge', (
    tester,
    size,
  ) async {
    await pumpAt(tester, menu(label: 'Export'), size: size);
    expect(tester.widget(find.byKey(buttonKey)), isA<QuarkBarChip>());
    expect(find.text('Export'), findsOneWidget);
    expect(
      tester.widget<MenuAnchor>(find.byType(MenuAnchor)).alignmentOffset,
      QuarkBarIconButton.menuAnchorOffset,
    );

    await tester.tap(find.byKey(buttonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(itemKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing an entry runs it and closes the menu', (tester) async {
    var chosen = 0;
    await pumpAt(tester, menu(onItem: () => chosen++));
    await tester.tap(find.byKey(buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(itemKey));
    await tester.pumpAndSettle();

    expect(chosen, 1);
    expect(find.byKey(itemKey), findsNothing);
  });

  testWidgets('selected tints the icon button and the chip', (tester) async {
    await pumpAt(tester, menu(selected: true));
    expect(
      tester.widget<QuarkBarIconButton>(find.byKey(buttonKey)).selected,
      isTrue,
    );

    await pumpAt(tester, menu(label: 'Person', selected: true));
    expect(tester.widget<QuarkBarChip>(find.byKey(buttonKey)).active, isTrue);
  });

  testWidgets('disabled refuses to open', (tester) async {
    await pumpAt(tester, menu(enabled: false));
    expect(
      tester.widget<QuarkBarIconButton>(find.byKey(buttonKey)).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(buttonKey), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(itemKey), findsNothing);
  });

  testWidgets('busy shows a spinner in the icon button', (tester) async {
    await pumpAt(tester, menu(isBusy: true));
    expect(
      tester.widget<QuarkBarIconButton>(find.byKey(buttonKey)).isBusy,
      isTrue,
    );
    expect(
      find.descendant(
        of: find.byKey(buttonKey),
        matching: find.byType(QuarkLoader),
      ),
      findsOneWidget,
    );
  });
}
