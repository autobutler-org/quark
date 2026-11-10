import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/layout/dismiss_keyboard_on_tap_outside.dart';

/// A tap outside the focused field closes the keyboard on a phone (#4051).
void main() {
  testWidgets(
    'a touch outside the focused field drops its focus',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final other = FocusNode();
      addTearDown(other.dispose);
      await tester.pumpWidget(
        DismissKeyboardOnTapOutside(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TextField(key: const ValueKey('a'), focusNode: focus),
                  TextField(key: const ValueKey('b'), focusNode: other),
                  const Expanded(child: SizedBox.expand()),
                ],
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();

      // Another field is not outside: focus moves to it.
      await tester.tap(find.byKey(const ValueKey('b')));
      await tester.pump();
      expect(other.hasFocus, isTrue);

      await tester.tapAt(const Offset(400, 500));
      await tester.pump();
      expect(other.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}
