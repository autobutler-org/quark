import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The floating month label over a sectioned photo grid (#979): it names the
/// section at the top while the grid scrolls, and only then.
void main() {
  final photos = [
    for (var i = 0; i < 60; i++) PhotoItem(id: 'p$i', name: 'p$i.jpg'),
  ];
  const sections = [
    PhotoGridSection(id: 'mar', label: 'March 2025', count: 30),
    PhotoGridSection(id: 'feb', label: 'February 2025', count: 30),
  ];
  const pill = ValueKey('photo_grid_scroll_label');

  Widget grid(ScrollController controller, {bool withSections = true}) =>
      CustomScrollView(
        controller: controller,
        slivers: [
          PhotoGrid(
            photos: photos,
            sections: withSections ? sections : null,
            crossAxisCount: 3,
            emptyState: const SizedBox(),
            thumbnailBuilder: (context, photo) => const SizedBox.expand(),
            onTap: (_) {},
            onLongPress: (_) {},
          ),
        ],
      );

  double opacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byKey(pill),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  String text(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(of: find.byKey(pill), matching: find.byType(Text)),
      )
      .data!;

  Future<ScrollController> pumpLabel(
    WidgetTester tester, {
    Size size = wideViewport,
    Brightness brightness = Brightness.dark,
    bool withSections = true,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpAt(
      tester,
      PhotoGridScrollLabel(child: grid(controller, withSections: withSections)),
      size: size,
      brightness: brightness,
    );
    await tester.pump();
    return controller;
  }

  testBothViewports('stays hidden until the grid scrolls', (
    tester,
    size,
  ) async {
    await pumpLabel(tester, size: size);

    expect(tester.takeException(), isNull);
    expect(text(tester), 'March 2025');
    expect(opacity(tester), 0);
  });

  testBothViewports('names the section in view while scrolling, then fades', (
    tester,
    size,
  ) async {
    final controller = await pumpLabel(tester, size: size);

    controller.jumpTo(40);
    await tester.pump();
    await tester.pump();

    expect(opacity(tester), 1);
    expect(text(tester), 'March 2025');

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    await tester.pump();

    expect(text(tester), 'February 2025');

    // Still up just before the timeout, gone once it passes.
    await tester.pump(const Duration(milliseconds: 1400));
    expect(opacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(opacity(tester), 0);
  });

  testWidgets('ignores another scrollable underneath it', (tester) async {
    final controller = ScrollController();
    final sidebar = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(sidebar.dispose);
    await pumpAt(
      tester,
      PhotoGridScrollLabel(
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: ListView(
                controller: sidebar,
                children: [for (var i = 0; i < 80; i++) Text('album $i')],
              ),
            ),
            Expanded(child: grid(controller)),
          ],
        ),
      ),
    );
    await tester.pump();

    sidebar.jumpTo(200);
    await tester.pump();
    await tester.pump();

    expect(opacity(tester), 0);
  });

  testWidgets('a grid without sections never shows it', (tester) async {
    final controller = await pumpLabel(tester, withSections: false);

    controller.jumpTo(200);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(pill), findsNothing);
  });

  testWidgets('takes no taps from the grid under it', (tester) async {
    final controller = await pumpLabel(tester);

    controller.jumpTo(40);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(pill).hitTestable(), findsNothing);
  });

  testWidgets('does not fade under reduced motion', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpAt(
      tester,
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: PhotoGridScrollLabel(child: grid(controller)),
      ),
    );
    await tester.pump();

    controller.jumpTo(40);
    await tester.pump();
    await tester.pump();

    final fade = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byKey(pill),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(fade.duration, Duration.zero);
    expect(fade.opacity, 1);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: colors come from the tokens', (tester) async {
      await pumpLabel(tester, brightness: brightness);

      expect(tester.takeException(), isNull);
      final style = tester
          .widget<Text>(
            find.descendant(of: find.byKey(pill), matching: find.byType(Text)),
          )
          .style!;
      expect(style.color, tokens.primary);
      final box = tester.widget<DecoratedBox>(find.byKey(pill));
      expect(
        (box.decoration as ShapeDecoration).color,
        tokens.card.withValues(alpha: 0.9),
      );
    });
  }
}
