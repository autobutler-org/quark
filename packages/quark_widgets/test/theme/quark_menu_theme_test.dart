import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// #4099: popup menus and [MenuAnchor] menus are one panel. [MenuAnchor] does
/// not read [PopupMenuTheme], so the panel has to be on [MenuTheme] too.
void main() {
  const sets = [
    ('dark', QuarkTokens.dark, Brightness.dark),
    ('light', QuarkTokens.light, Brightness.light),
    ('high-contrast dark', QuarkTokens.highContrastDark, Brightness.dark),
    ('high-contrast light', QuarkTokens.highContrastLight, Brightness.light),
  ];

  for (final (name, tokens, brightness) in sets) {
    test('$name: both menus are the card, at the card radius', () {
      final theme = QuarkTheme.from(tokens, brightness);
      final menu = theme.menuTheme.style!;
      final shape =
          menu.shape!.resolve(<WidgetState>{})! as RoundedRectangleBorder;
      final popupShape = theme.popupMenuTheme.shape! as RoundedRectangleBorder;
      final background = menu.backgroundColor!.resolve(<WidgetState>{});

      expect(background, tokens.card);
      expect(background, isNot(tokens.background));
      expect(theme.popupMenuTheme.color, background);
      expect(popupShape.borderRadius, BorderRadius.circular(tokens.radiusLg));
      expect(shape.borderRadius, popupShape.borderRadius);
      expect(popupShape.side.color, shape.side.color);
      // The card is about 1.1:1 from the canvas and the hairline border about
      // 1.3:1, so the edge itself has to clear 3:1 on both.
      expect(
        contrastRatio(shape.side.color, tokens.background),
        greaterThanOrEqualTo(3),
      );
      expect(
        contrastRatio(shape.side.color, tokens.card),
        greaterThanOrEqualTo(3),
      );
      // Anchors already use 160, 200, and 220. The theme must not pick one.
      expect(menu.minimumSize, isNull);
      expect(
        menu.padding!.resolve(<WidgetState>{}),
        EdgeInsets.symmetric(vertical: tokens.spacingSm),
      );
      expect(
        theme.popupMenuTheme.menuPadding,
        EdgeInsets.symmetric(vertical: tokens.spacingSm),
      );
    });

    test(
      '$name: a menu row is shorter than a list tile, with one icon size',
      () {
        final theme = QuarkTheme.from(tokens, brightness);
        final button = theme.menuButtonTheme.style!;
        final height = button.minimumSize!.resolve(<WidgetState>{})!.height;
        final iconSize = button.iconSize!.resolve(<WidgetState>{});

        // A one-line list tile is 56. The row stays a 48dp target.
        expect(height, lessThan(56));
        expect(height, greaterThanOrEqualTo(kMinInteractiveDimension));
        expect(iconSize, theme.iconTheme.size);
        expect(button.iconSize!.resolve({WidgetState.hovered}), iconSize);
        expect(button.iconSize!.resolve({WidgetState.selected}), iconSize);

        final hover = button.overlayColor!.resolve({WidgetState.hovered})!;
        final selected = button.overlayColor!.resolve({WidgetState.selected})!;
        final resting = button.overlayColor!.resolve(<WidgetState>{})!;
        expect(hover.a, greaterThan(0));
        expect(selected.a, greaterThan(0));
        expect(resting.a, 0);

        final focused = button.side!.resolve({WidgetState.focused})!;
        expect(focused.color, tokens.focus);
        expect(focused.width, tokens.focusRingWidth);
        expect(focused.width, greaterThanOrEqualTo(2));
      },
    );
  }

  for (final (name, tokens, brightness) in [
    ('dark', QuarkTokens.dark, Brightness.dark),
    ('light', QuarkTokens.light, Brightness.light),
  ]) {
    testWidgets('$name: an anchor menu and a popup paint the same panel', (
      tester,
    ) async {
      await pumpAt(
        tester,
        MenuAnchor(
          style: const MenuStyle(
            minimumSize: WidgetStatePropertyAll(Size(200, 0)),
          ),
          menuChildren: [
            MenuItemButton(onPressed: () {}, child: const Text('Anchor row')),
          ],
          builder: (context, menu, _) => TextButton(
            onPressed: menu.open,
            child: const Text('Open anchor'),
          ),
        ),
        brightness: brightness,
      );
      await tester.tap(find.text('Open anchor'));
      await tester.pumpAndSettle();

      final (anchor, _) = _panelBehind(tester, find.text('Anchor row'));
      final anchorShape = anchor.shape! as RoundedRectangleBorder;
      expect(anchor.color, tokens.card);
      expect(anchor.color, isNot(tokens.background));
      expect(anchorShape.borderRadius, BorderRadius.circular(tokens.radiusLg));
      expect(
        contrastRatio(anchorShape.side.color, tokens.background),
        greaterThanOrEqualTo(3),
      );
      // The anchor asked for 200. The theme did not replace that width.
      final widths = <double>[];
      tester.element(find.text('Anchor row')).visitAncestorElements((ancestor) {
        final box = ancestor.renderObject;
        if (box is RenderBox && box.hasSize) widths.add(box.size.width);
        return true;
      });
      expect(
        widths.any((width) => width >= 200),
        isTrue,
        reason: 'laid-out widths: $widths',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpAt(
        tester,
        PopupMenuButton<int>(
          itemBuilder: (context) => const [
            PopupMenuItem(value: 1, child: Text('Popup row')),
          ],
        ),
        brightness: brightness,
      );
      await tester.tap(find.byType(PopupMenuButton<int>));
      await tester.pumpAndSettle();

      final (popup, _) = _panelBehind(tester, find.text('Popup row'));
      final popupShape = popup.shape! as RoundedRectangleBorder;
      expect(popup.color, anchor.color);
      expect(popupShape.borderRadius, anchorShape.borderRadius);
      expect(popupShape.side.color, anchorShape.side.color);
    });
  }
}

/// The menu panel is the nearest filled, shaped [Material] behind [item],
/// with the size it laid out at.
///
/// A menu row's own ink material is transparent and would hide the panel.
(Material, Size) _panelBehind(WidgetTester tester, Finder item) {
  Material? found;
  Size? size;
  tester.element(item).visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Material &&
        widget.shape is RoundedRectangleBorder &&
        (widget.color?.a ?? 0) > 0) {
      found = widget;
      final box = ancestor.renderObject;
      if (box is RenderBox) size = box.size;
      return false;
    }
    return true;
  });
  expect(found, isNotNull);
  expect(size, isNotNull);
  return (found!, size!);
}
