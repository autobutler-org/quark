import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _records = [
  RecordListItem(id: 'a', title: 'This browser', subtitle: 'Last active now'),
  RecordListItem(
    id: 'b',
    title: 'Safari on iPhone',
    subtitle: 'Last active yesterday',
    hasAction: false,
  ),
];

Finder _tile(String id) => find.byKey(ValueKey('device_tile_$id'));
Finder _button(String id) => find.byKey(ValueKey('device_remove_$id'));

RecordListCard _card({
  List<RecordListItem> records = _records,
  bool isLoading = false,
  String? error,
  bool collapsible = false,
  VoidCallback? onRefresh,
  ValueChanged<String>? onAction,
  Widget? footer,
}) => RecordListCard(
  title: 'Devices',
  subtitle: 'Where you are signed in',
  records: records,
  keyPrefix: 'device',
  actionKey: 'remove',
  actionIcon: QuarkIcons.delete_outline,
  actionTooltip: 'Remove',
  onAction: onAction,
  isLoading: isLoading,
  error: error,
  emptyText: 'Nothing yet',
  collapsible: collapsible,
  onRefresh: onRefresh,
  footer: footer,
);

/// A settings card listing records with one action each (#4104).
void main() {
  testBothViewports('title, subtitle, rows and footer fit', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      SingleChildScrollView(
        child: _card(
          onAction: (_) {},
          footer: TextButton(onPressed: () {}, child: const Text('All')),
        ),
      ),
      size: size,
    );

    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Where you are signed in'), findsOneWidget);
    expect(_tile('a'), findsOneWidget);
    expect(_tile('b'), findsOneWidget);
    expect(find.text('Last active yesterday'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Nothing yet'), findsNothing);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(tester.getRect(_tile('a')).right, lessThanOrEqualTo(size.width));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the button fires with the row id, only where allowed', (
    tester,
  ) async {
    final ids = <String>[];
    await pumpAt(tester, _card(onAction: ids.add));

    expect(_button('b'), findsNothing);
    await tester.tap(_button('a'));
    expect(ids, ['a']);
  });

  testWidgets('a null onAction disables the buttons', (tester) async {
    await pumpAt(tester, _card());

    expect(tester.widget<IconButton>(_button('a')).onPressed, isNull);
  });

  testWidgets('loading shows the loader and no empty row', (tester) async {
    await pumpAt(tester, _card(records: const [], isLoading: true));

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.text('Nothing yet'), findsNothing);
  });

  testWidgets('an error shows its row beside the rows given', (tester) async {
    await pumpAt(tester, _card(error: 'Could not load'));

    expect(find.text('Could not load'), findsOneWidget);
    expect(find.byIcon(QuarkIcons.error_outline), findsOneWidget);
    expect(_tile('a'), findsOneWidget);
    expect(find.text('Nothing yet'), findsNothing);
  });

  testWidgets('no records shows the empty row', (tester) async {
    await pumpAt(tester, _card(records: const []));

    expect(find.text('Nothing yet'), findsOneWidget);
  });

  testWidgets('collapsible starts folded and opens on a tap, refresh fires', (
    tester,
  ) async {
    var refreshes = 0;
    await pumpAt(
      tester,
      _card(collapsible: true, onRefresh: () => refreshes++),
    );

    expect(_tile('a'), findsNothing);
    await tester.tap(find.text('Devices'));
    await tester.pumpAndSettle();
    expect(_tile('a'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('refresh_button')));
    expect(refreshes, 1);
    expect(find.byTooltip('Refresh devices'), findsOneWidget);
  });
}
