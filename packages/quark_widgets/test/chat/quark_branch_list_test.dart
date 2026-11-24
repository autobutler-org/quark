import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// A channel's side conversations (#4351): newest first, quiet ones folded
/// under a heading at the bottom, a parent that can't be shown named as
/// unavailable, and loading, error and empty drawn as asked.
void main() {
  final now = DateTime.now();
  final quietBefore = now.subtract(const Duration(days: 7));

  ChatMessageItem branch(
    String id,
    String body,
    Duration ago, {
    ChatMessageKind kind = ChatMessageKind.text,
    bool unread = false,
  }) => ChatMessageItem(
    id: id,
    authorId: 'ada',
    authorName: 'Ada',
    sentAt: now.subtract(const Duration(days: 30)),
    body: body,
    kind: kind,
    branch: ChatBranchItem(
      replyCount: 3,
      lastReplyAt: now.subtract(ago),
      hasUnread: unread,
    ),
  );

  final branches = [
    branch('1', 'The sink is leaking\nUnder the kitchen one', Duration.zero),
    branch('2', '', const Duration(hours: 2), kind: ChatMessageKind.deleted),
    branch('3', 'Holiday plans', const Duration(days: 20)),
  ];

  Future<void> pump(
    WidgetTester tester,
    Size size, {
    List<ChatMessageItem>? items,
    bool expanded = false,
    bool isLoading = false,
    String? error,
    bool hasMore = false,
    List<String>? opened,
    List<bool>? toggles,
    VoidCallback? onLoadMore,
  }) => pumpAt(
    tester,
    QuarkBranchList(
      branches: items ?? branches,
      quietBefore: quietBefore,
      isQuietExpanded: expanded,
      onQuietExpandedChanged: toggles?.add,
      isLoading: isLoading,
      error: error,
      hasMore: hasMore,
      onLoadMore: onLoadMore,
      onOpen: opened?.add ?? (_) {},
    ),
    size: size,
  );

  const row1 = ValueKey('branch_row_1');
  const row2 = ValueKey('branch_row_2');
  const row3 = ValueKey('branch_row_3');
  const quiet = ValueKey('branch_list_quiet');

  testBothViewports('lists active rows first and folds quiet ones away', (
    tester,
    size,
  ) async {
    final opened = <String>[];
    final toggles = <bool>[];
    await pump(tester, size, opened: opened, toggles: toggles);

    expect(find.text('The sink is leaking'), findsOneWidget);
    expect(find.text('Original message unavailable'), findsOneWidget);
    expect(find.text('Ada · 3 replies, last just now'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(row1)).dy,
      lessThan(tester.getTopLeft(find.byKey(row2)).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(row2)).dy,
      lessThan(tester.getTopLeft(find.byKey(quiet)).dy),
    );
    expect(find.text('Quiet (1)'), findsOneWidget);
    expect(find.byKey(row3), findsNothing);

    await tester.tap(find.byKey(quiet));
    await tester.tap(find.byKey(row2));
    expect(toggles, [true]);
    expect(opened, ['2']);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('an expanded Quiet shows its rows under the heading', (
    tester,
    size,
  ) async {
    final opened = <String>[];
    await pump(tester, size, expanded: true, opened: opened);

    expect(
      tester.getTopLeft(find.byKey(quiet)).dy,
      lessThan(tester.getTopLeft(find.byKey(row3)).dy),
    );
    await tester.tap(find.byKey(row3));
    expect(opened, ['3']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a quiet branch with a new reply is above the fold again', (
    tester,
  ) async {
    await pump(
      tester,
      wideViewport,
      items: [branch('3', 'Holiday plans', Duration.zero)],
    );
    expect(find.byKey(row3), findsOneWidget);
    expect(find.byKey(quiet), findsNothing);
  });

  testBothViewports('loading, error and empty', (tester, size) async {
    await pump(tester, size, items: const [], isLoading: true);
    expect(find.byKey(const ValueKey('branch_list_loading')), findsOneWidget);

    await pump(tester, size, items: const [], error: "Couldn't load them.");
    expect(find.byKey(const ValueKey('branch_list_error')), findsOneWidget);
    expect(find.byKey(row1), findsNothing);

    await pump(tester, size, items: const []);
    expect(find.byKey(const ValueKey('branch_list_empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Load more pages, or waits while a page loads', (tester) async {
    var loads = 0;
    await pump(
      tester,
      narrowViewport,
      hasMore: true,
      onLoadMore: () => loads++,
    );
    await tester.tap(find.byKey(const ValueKey('branch_list_load_more')));
    expect(loads, 1);

    await pump(
      tester,
      narrowViewport,
      hasMore: true,
      isLoading: true,
      onLoadMore: () => loads++,
    );
    expect(find.byKey(const ValueKey('branch_list_load_more')), findsNothing);
    expect(find.byKey(const ValueKey('branch_list_loading')), findsOneWidget);
    expect(find.byKey(row1), findsOneWidget);
  });
}
