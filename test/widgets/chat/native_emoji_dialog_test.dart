import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/chat/native_emoji_dialog.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The mobile reaction field (#3452): the system keyboard's first emoji is
/// the reaction, and closing the dialog without one sends nothing.
void main() {
  const field = ValueKey('native_emoji_field');
  const narrow = Size(360, 640);
  const wide = Size(1280, 800);

  Future<void> pumpDialog(
    WidgetTester tester,
    Size size, {
    required ValueChanged<String> onPick,
    required VoidCallback onCancel,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: NativeEmojiDialog(onPick: onPick, onCancel: onCancel),
        ),
      ),
    );
  }

  for (final size in [narrow, wide]) {
    testWidgets('the first emoji is the reaction at ${size.width} wide', (
      tester,
    ) async {
      String? picked;
      var cancels = 0;
      await pumpDialog(
        tester,
        size,
        onPick: (emoji) => picked = emoji,
        onCancel: () => cancels += 1,
      );

      await tester.enterText(find.byKey(field), 'hello');
      await tester.pump();
      expect(picked, isNull);

      await tester.enterText(find.byKey(field), 'hello🎉');
      await tester.pump();
      expect(picked, '🎉');
      expect(cancels, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a flag and a heart each count as one emoji', (tester) async {
    String? picked;
    await pumpDialog(
      tester,
      wide,
      onPick: (emoji) => picked = emoji,
      onCancel: () {},
    );
    await tester.enterText(find.byKey(field), '🇬🇧');
    await tester.pump();
    expect(picked, '🇬🇧');

    picked = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpDialog(
      tester,
      wide,
      onPick: (emoji) => picked = emoji,
      onCancel: () {},
    );
    await tester.enterText(find.byKey(field), '❤️');
    await tester.pump();
    expect(picked, '❤️');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel sends nothing', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showNativeEmojiDialog(context).then((emoji) {
                  result = emoji;
                });
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('native_emoji_cancel')));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  test('the native keyboard is only for Android and iOS', () {
    expect(
      useNativeEmojiKeyboard(isWeb: true, platform: TargetPlatform.android),
      isFalse,
    );
    expect(
      useNativeEmojiKeyboard(isWeb: false, platform: TargetPlatform.android),
      isTrue,
    );
    expect(
      useNativeEmojiKeyboard(isWeb: false, platform: TargetPlatform.iOS),
      isTrue,
    );
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.fuchsia,
    ]) {
      expect(useNativeEmojiKeyboard(isWeb: false, platform: platform), isFalse);
    }
  });
}
