import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The ratio WCAG asks of a control's boundary and its glyph (1.4.11).
const double _boundary = 3;

/// #3257: in dark mode the composer's border, the send button and the
/// message row's icons were faint. Measured as drawn, in every preset, on
/// the surfaces the chat sits on.
void main() {
  for (final themeColor in QuarkThemeColor.presets) {
    final tokens = themeColor.tokensFor(Brightness.dark);
    final surfaces = {'background': tokens.background, 'card': tokens.card};

    void expectAtLeast3(String label, Color color, Map<String, Color> on) {
      for (final MapEntry(key: surface, value: under) in on.entries) {
        expect(
          contrastRatio(color, under),
          greaterThanOrEqualTo(_boundary),
          reason: '${themeColor.storageValue}: $label on $surface',
        );
      }
    }

    testWidgets('chat controls reach 3:1 in ${themeColor.storageValue} dark', (
      tester,
    ) async {
      await pumpAt(
        tester,
        Column(
          children: [
            Expanded(
              child: QuarkMessageList(
                messages: [
                  ChatMessageItem(
                    id: 'm1',
                    authorId: 'ada',
                    authorName: 'Ada',
                    sentAt: DateTime(2026, 9, 24),
                    body: 'hello',
                  ),
                ],
                onCopy: (_) {},
                onReact: (_, _) {},
              ),
            ),
            QuarkMessageComposer(onSend: (_) {}),
          ],
        ),
        themeColor: themeColor,
      );

      Color iconIn(String key) {
        final icon = find
            .descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Icon),
            )
            .first;
        return tester.widget<Icon>(icon).color ??
            IconTheme.of(tester.element(icon)).color!;
      }

      Material sendMaterial() => tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(const ValueKey('message_composer_send')),
              matching: find.byType(Material),
            )
            .first,
      );

      expectAtLeast3('add reaction', iconIn('message_react_m1'), surfaces);
      // The three-dot button is the pointer presentation's, so this runs as
      // macOS; `flutter test` is Android, which has none.
      expectAtLeast3('message menu', iconIn('message_menu_m1'), surfaces);

      final field = tester.widget<InputDecorator>(find.byType(InputDecorator));
      final border = field.decoration.enabledBorder!.borderSide.color;
      expectAtLeast3('composer border', border, {
        ...surfaces,
        'input': tokens.input,
      });

      // Empty, so disabled: an outlined input, with a glyph legible on it.
      final idle = sendMaterial();
      final idleFill = Color.alphaBlend(idle.color!, tokens.background);
      final idleSide = (idle.shape! as OutlinedBorder).side.color;
      expectAtLeast3('idle send outline', idleSide, surfaces);
      expectAtLeast3('idle send glyph', iconIn('message_composer_send'), {
        'its fill': idleFill,
      });

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pumpAndSettle();

      final ready = sendMaterial();
      final readyFill = Color.alphaBlend(ready.color!, tokens.background);
      expectAtLeast3('send button', readyFill, surfaces);
      expectAtLeast3('send glyph', iconIn('message_composer_send'), {
        'its fill': readyFill,
      });
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
}
