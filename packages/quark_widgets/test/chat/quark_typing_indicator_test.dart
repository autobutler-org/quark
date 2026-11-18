import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// Who else is typing (#2426): named up to two, counted past that, and no
/// space at all when nobody is.
void main() {
  test('names one or two, then says several', () {
    expect(QuarkTypingIndicator.sentence(const []), '');
    expect(QuarkTypingIndicator.sentence(const ['ada']), 'ada is typing');
    expect(
      QuarkTypingIndicator.sentence(const ['ada', 'bob']),
      'ada and bob are typing',
    );
    expect(
      QuarkTypingIndicator.sentence(const ['ada', 'bob', 'carol']),
      'Several people are typing',
    );
  });

  testBothViewports('draws one line, and nothing for nobody', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkTypingIndicator(names: ['a very long name ' * 20]),
      size: size,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('typing_indicator')))
          .maxLines,
      1,
    );
    expect(tester.takeException(), isNull);

    await pumpAt(tester, const QuarkTypingIndicator(names: []), size: size);
    expect(find.byKey(const ValueKey('typing_indicator')), findsNothing);
  });
}
