import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/properties/slide_alt_text_field.dart';
import 'package:quark/widgets/slides/properties/slide_number_field.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;

/// The properties panel's fields (#1167): a value is submitted once, when
/// editing ends, so it is one undo step.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
    home: Scaffold(
      body: Center(child: SizedBox(width: 240, child: child)),
    ),
  );

  test('numbers show whole when they are whole', () {
    expect(SlideNumberField.format(640), '640');
    expect(SlideNumberField.format(12.25), '12.3');
  });

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('a number is submitted on Enter, once ($name)', (tester) async {
      tap.setViewport(tester, size);
      final submitted = <double>[];
      await tester.pumpWidget(
        host(
          SlideNumberField(
            key: const ValueKey('x'),
            label: 'X',
            value: 100,
            onSubmitted: submitted.add,
          ),
        ),
      );
      expect(find.text('100'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('x')), '25');
      expect(submitted, isEmpty, reason: 'typing alone submits nothing');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, [25]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('text that is not a number puts the value back', (tester) async {
    final submitted = <double>[];
    await tester.pumpWidget(
      host(
        SlideNumberField(
          key: const ValueKey('x'),
          label: 'X',
          value: 100,
          onSubmitted: submitted.add,
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('x')), '-');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, isEmpty);
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('a new value shows when the field is not being edited', (
    tester,
  ) async {
    Widget field(double v) =>
        host(SlideNumberField(label: 'Width', value: v, onSubmitted: (_) {}));
    await tester.pumpWidget(field(100));
    await tester.pumpWidget(field(250));
    expect(find.text('250'), findsOneWidget);
  });

  testWidgets('alt text is saved when editing ends', (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(
      host(SlideAltTextField(value: '', onSubmitted: saved.add)),
    );
    await tester.enterText(
      find.byKey(const ValueKey('slide_prop_alt_text')),
      'A dog on a beach',
    );
    expect(saved, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(saved, ['A dog on a beach']);
  });
}
