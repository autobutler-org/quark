import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _onChromeKey = ValueKey('on_chrome');
const _onContentKey = ValueKey('on_content');

/// The style a bar button resolved for itself.
ButtonStyle _styleOf(WidgetTester tester, Key key) => tester
    .widget<IconButton>(
      find.descendant(of: find.byKey(key), matching: find.byType(IconButton)),
    )
    .style!;

/// Chrome is colored and content is tinted (#2740), so a widget has to know
/// which of the two it is drawn on. `QuarkChrome` is how it finds out.
void main() {
  for (final brightness in Brightness.values) {
    testBothViewports(
      '${brightness.name}: tokens under it are the chrome set',
      (tester, size) async {
        late QuarkTokens outside;
        late QuarkTokens inside;
        late bool outsideIsOn;
        late bool insideIsOn;
        await pumpAt(
          tester,
          Builder(
            builder: (context) {
              outside = QuarkTokens.of(context);
              outsideIsOn = QuarkChrome.isOn(context);
              return QuarkChrome(
                child: Builder(
                  builder: (context) {
                    inside = QuarkTokens.of(context);
                    insideIsOn = QuarkChrome.isOn(context);
                    return const SizedBox.shrink();
                  },
                ),
              );
            },
          ),
          size: size,
          brightness: brightness,
          themeColor: QuarkThemeColor.violet,
        );

        final tokens = QuarkThemeColor.violet.tokensFor(brightness);
        expect(outsideIsOn, isFalse);
        expect(insideIsOn, isTrue);
        expect(outside, tokens);
        expect(inside, tokens.onChrome);
        expect(inside.foreground, tokens.chromeForeground);
        expect(inside, isNot(outside));
      },
    );

    testBothViewports(
      '${brightness.name}: the same bar button draws for where it sits',
      (tester, size) async {
        const button = QuarkBarIconButton(
          icon: QuarkIcons.search,
          tooltip: 'Search',
          onPressed: null,
        );
        await pumpAt(
          tester,
          const Column(
            children: [
              KeyedSubtree(key: _onContentKey, child: button),
              QuarkChrome(
                child: KeyedSubtree(key: _onChromeKey, child: button),
              ),
            ],
          ),
          size: size,
          brightness: brightness,
          themeColor: QuarkThemeColor.pink,
        );

        final tokens = QuarkThemeColor.pink.tokensFor(brightness);
        final onContent = _styleOf(tester, _onContentKey);
        final onChrome = _styleOf(tester, _onChromeKey);
        expect(
          onContent.foregroundColor!.resolve({}),
          tokens.secondaryForeground,
        );
        expect(onContent.side!.resolve({})!.color, tokens.border);
        expect(
          onContent.foregroundColor!.resolve({WidgetState.disabled}),
          tokens.mutedForeground,
        );
        expect(
          onChrome.foregroundColor!.resolve({}),
          tokens.chromeSecondaryForeground,
        );
        expect(onChrome.side!.resolve({})!.color, tokens.chromeBorder);
        expect(
          onChrome.foregroundColor!.resolve({WidgetState.disabled}),
          tokens.chromeMutedForeground,
        );
        // The fill is the content's input either way.
        expect(onChrome.backgroundColor!.resolve({}), tokens.input);
        expect(onContent.backgroundColor!.resolve({}), tokens.input);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testBothViewports('classic draws the same on chrome as off it', (
    tester,
    size,
  ) async {
    late QuarkTokens inside;
    await pumpAt(
      tester,
      QuarkChrome(
        child: Builder(
          builder: (context) {
            inside = QuarkTokens.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
      size: size,
    );

    expect(inside, QuarkTokens.dark);
  });

  testBothViewports('a menu opened from the chrome is not on it', (
    tester,
    size,
  ) async {
    late QuarkTokens inMenu;
    await pumpAt(
      tester,
      QuarkChrome(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMenu<void>(
              context: context,
              position: RelativeRect.fill,
              items: [
                PopupMenuItem(
                  child: Builder(
                    builder: (context) {
                      inMenu = QuarkTokens.of(context);
                      return const Text('Rename');
                    },
                  ),
                ),
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      size: size,
      themeColor: QuarkThemeColor.lime,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(inMenu, QuarkThemeColor.lime.tokensFor(Brightness.dark));
  });
}
