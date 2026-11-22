import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// A side conversation beside its channel (#4347): a header named for the
/// parent's first line, the parent, then the caller's replies and composer.
void main() {
  const replies = ValueKey('replies_body');
  const composer = ValueKey('composer_body');

  ChatMessageItem parentOf(
    String body, {
    ChatMessageKind kind = ChatMessageKind.text,
  }) => ChatMessageItem(
    id: 'p1',
    authorId: 'ada',
    authorName: 'Ada',
    sentAt: DateTime(2026, 11, 22, 9),
    body: body,
    kind: kind,
  );

  QuarkBranchPanel panel(ChatMessageItem? parent, {VoidCallback? onClose}) =>
      QuarkBranchPanel(
        parent: parent,
        onClose: onClose ?? () {},
        messages: const SizedBox.expand(key: replies),
        composer: const SizedBox(key: composer, height: 56),
      );

  testBothViewports('draws the header, the parent, replies and composer', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      panel(parentOf('The sink is leaking\nUnder the kitchen one')),
      size: size,
    );

    expect(find.text('The sink is leaking'), findsOneWidget);
    expect(find.text('The sink is leaking\nUnder the kitchen one'), findsOne);
    expect(find.byKey(const ValueKey('branch_panel_parent')), findsOneWidget);
    expect(find.byKey(replies), findsOneWidget);
    expect(find.byKey(composer), findsOneWidget);
    // Header, parent, replies, composer, top to bottom.
    final title = tester.getTopLeft(
      find.byKey(const ValueKey('branch_panel_title')),
    );
    final parent = tester.getTopLeft(
      find.byKey(const ValueKey('branch_panel_parent')),
    );
    expect(title.dy, lessThan(parent.dy));
    expect(parent.dy, lessThan(tester.getTopLeft(find.byKey(replies)).dy));
    expect(
      tester.getBottomLeft(find.byKey(replies)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(composer)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('a long first line does not overflow the header', (
    tester,
    size,
  ) async {
    final long = List.filled(40, 'leaking').join(' ');
    await pumpAt(tester, panel(parentOf(long)), size: size);

    final title = tester.widget<Text>(
      find.byKey(const ValueKey('branch_panel_title')),
    );
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(
      tester.getTopRight(find.byKey(const ValueKey('branch_panel_close'))).dx,
      lessThanOrEqualTo(size.width),
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('a long parent scrolls and leaves the replies room', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      panel(parentOf(List.filled(80, 'line').join('\n'))),
      size: size,
    );

    expect(
      tester.getSize(find.byKey(replies)).height,
      greaterThan(
        tester
            .getSize(find.byKey(const ValueKey('branch_panel_parent')))
            .height,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  for (final (label, parent) in [
    ('missing', null),
    ('deleted', parentOf('', kind: ChatMessageKind.deleted)),
    ('waiting for its key', parentOf('', kind: ChatMessageKind.waitingForKey)),
  ]) {
    testWidgets('a $label parent reads as unavailable', (tester) async {
      await pumpAt(tester, panel(parent));

      expect(
        find.byKey(const ValueKey('branch_panel_parent_unavailable')),
        findsOneWidget,
      );
      expect(find.text('Original message unavailable'), findsOneWidget);
      expect(find.text(QuarkBranchPanel.fallbackTitle), findsOneWidget);
      expect(find.byKey(replies), findsOneWidget);
    });
  }

  testWidgets('the close button calls back', (tester) async {
    var closed = 0;
    await pumpAt(tester, panel(parentOf('hi'), onClose: () => closed++));

    await tester.tap(find.byKey(const ValueKey('branch_panel_close')));
    expect(closed, 1);
  });

  testWidgets('inside a sheet it leaves its header to the sheet', (
    tester,
  ) async {
    await pumpAt(
      tester,
      QuarkSheet(
        title: 'The sink is leaking',
        onClose: () {},
        scrollable: false,
        child: panel(parentOf('The sink is leaking')),
      ),
      size: narrowViewport,
    );

    expect(find.byKey(const ValueKey('branch_panel_title')), findsNothing);
    expect(find.byKey(const ValueKey('branch_panel_close')), findsNothing);
    expect(find.byKey(const ValueKey('quark_sheet_close')), findsOneWidget);
    expect(find.byKey(replies), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('titleFor takes the first line that is not blank', () {
    expect(QuarkBranchPanel.titleFor(parentOf('\n  \n  Sink  \nmore')), 'Sink');
    expect(QuarkBranchPanel.titleFor(parentOf('')), 'Side conversation');
    expect(QuarkBranchPanel.titleFor(null), 'Side conversation');
  });
}
