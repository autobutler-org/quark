import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('refreshes through its callback', (tester, size) async {
    var refreshes = 0;
    await pumpAt(
      tester,
      RefreshIconButton(isRefreshing: false, onPressed: () => refreshes++),
      size: size,
    );

    expect(find.byIcon(QuarkIcons.refresh), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('refresh_button')));
    await tester.pump();

    expect(refreshes, 1);
  });

  testBothViewports('spins and refuses taps while refreshing', (
    tester,
    size,
  ) async {
    var refreshes = 0;
    await pumpAt(
      tester,
      RefreshIconButton(isRefreshing: true, onPressed: () => refreshes++),
      size: size,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(QuarkIcons.refresh), findsNothing);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(refreshes, 0);
  });

  testWidgets('is disabled outright when given no callback', (tester) async {
    await pumpAt(
      tester,
      const RefreshIconButton(isRefreshing: false, onPressed: null),
      size: narrowViewport,
    );

    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
  });

  testWidgets('uses the tooltip it is given', (tester) async {
    await pumpAt(
      tester,
      RefreshIconButton(
        isRefreshing: false,
        onPressed: () {},
        tooltip: 'Reload photos',
      ),
      size: wideViewport,
    );

    expect(find.byTooltip('Reload photos'), findsOneWidget);
  });

  testBothViewports('looks the same inside an app bar as outside one', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      Column(
        children: [
          AppBar(
            leading: RefreshIconButton(
              key: const ValueKey('in_bar'),
              isRefreshing: false,
              onPressed: () {},
            ),
          ),
          RefreshIconButton(
            key: const ValueKey('in_body'),
            isRefreshing: false,
            onPressed: () {},
          ),
        ],
      ),
      size: size,
    );

    RenderParagraph glyph(String key) => tester.renderObject(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(RichText),
      ),
    );
    final inBar = glyph('in_bar').text.style!;
    final inBody = glyph('in_body').text.style!;
    expect(inBar.fontSize, inBody.fontSize);
    expect(inBar.color, inBody.color);
  });
}
