import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The strip above the composer while a message is being edited (#2426): it
/// says so, shows the message on one line, and cancels.
void main() {
  testBothViewports('shows the title and one line of text, and cancels', (
    tester,
    size,
  ) async {
    var canceled = 0;
    await pumpAt(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: QuarkComposerContextBar(
          icon: QuarkIcons.edit_outlined,
          title: 'Editing message',
          text: 'Dinner at 7 ' * 40,
          onCancel: () => canceled++,
        ),
      ),
      size: size,
    );

    expect(find.text('Editing message'), findsOneWidget);
    final line = tester.widget<Text>(find.textContaining('Dinner at 7'));
    expect(line.maxLines, 1);
    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);

    await tester.tap(find.byKey(const ValueKey('composer_context_cancel')));
    expect(canceled, 1);
  });

  testWidgets('without text shows only the title', (tester) async {
    await pumpAt(
      tester,
      QuarkComposerContextBar(
        icon: QuarkIcons.edit_outlined,
        title: 'Editing message',
        onCancel: () {},
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('composer_context')),
        matching: find.byType(Text),
      ),
      findsOneWidget,
    );
  });
}
