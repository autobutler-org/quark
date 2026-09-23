// A complete widget test covering the whole checklist in ../SKILL.md.
//
// To use it:
//   1. Copy to `test/<group>/<your_widget>_test.dart`.
//   2. Change the `pump.dart` import to `../support/pump.dart`.
//   3. Delete the "the widget under test" section at the bottom and import
//      your own widget instead.
//   4. Rename `ThingList`/`Thing` throughout and fix the key prefixes.
//
// It sits here rather than under `test/` so `flutter analyze` and
// `dart format --set-exit-if-changed` keep it compiling, which is the only
// way a template stays honest.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../test/support/pump.dart';

/// Fake data. Three items is enough to prove per-item keys and indexing, and
/// small enough to read in a failure message.
const threeThings = [
  Thing(id: 'a', name: 'Alpha'),
  Thing(id: 'b', name: 'Beta'),
  Thing(id: 'c', name: 'Gamma'),
];

void main() {
  // 1. Every declared state renders, and hides the others.

  testBothViewports('shows a spinner while loading', (tester, size) async {
    await pumpAt(
      tester,
      const ThingList(items: [], isLoading: true),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
  });

  testBothViewports('shows the empty copy when there is nothing', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const ThingList(items: []), size: size);

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('renders the error the caller handed it', (
    tester,
    size,
  ) async {
    // The package never composes error copy. It renders the caller's string.
    await pumpAt(
      tester,
      const ThingList(items: [], error: 'Host unreachable'),
      size: size,
    );

    expect(find.text('Host unreachable'), findsOneWidget);
  });

  testBothViewports('renders one row per item', (tester, size) async {
    await pumpAt(tester, const ThingList(items: threeThings), size: size);

    expect(find.byKey(const ValueKey('thing_row_a')), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testBothViewports('marks the selected item', (tester, size) async {
    await pumpAt(
      tester,
      const ThingList(items: threeThings, selectedIds: {'b'}),
      size: size,
    );

    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  // 2. Both viewports lay out cleanly.

  testBothViewports('lays out without an exception', (tester, size) async {
    await pumpAt(tester, const ThingList(items: threeThings), size: size);

    expect(tester.takeException(), isNull);
  });

  // 3. Every callback fires exactly once, with the right value.

  testBothViewports('reports the item that was tapped', (tester, size) async {
    final selected = <String>[];
    await pumpAt(
      tester,
      ThingList(items: threeThings, onSelect: selected.add),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('thing_row_b')));
    await tester.pump();

    // A list, not a bool: a second fire fails here, a bool would hide it.
    expect(selected, ['b']);
  });

  testBothViewports('emits every action it offers, in order', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      ThingList(
        items: threeThings,
        onSelect: (id) => events.add('select:$id'),
        onDelete: (id) => events.add('delete:$id'),
      ),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('thing_row_a')));
    await tester.tap(find.byKey(const ValueKey('thing_delete_c')));
    await tester.pump();

    expect(events, ['select:a', 'delete:c']);
  });

  testWidgets('dims the delete button when deleting is not offered', (
    tester,
  ) async {
    await pumpAt(tester, const ThingList(items: threeThings));

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('thing_delete_b')),
    );
    expect(button.onPressed, isNull);
  });

  // 4. Every documented key prefix is present, per item.

  testWidgets('emits every documented key for every item', (tester) async {
    await pumpAt(tester, const ThingList(items: threeThings));

    for (final thing in threeThings) {
      expect(find.byKey(ValueKey('thing_row_${thing.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('thing_delete_${thing.id}')), findsOneWidget);
    }
  });

  // 5. Both token sets render, and the colors come from the tokens.

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: colors come from the tokens', (tester) async {
      await pumpAt(
        tester,
        const ThingList(items: threeThings),
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      final box = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('thing_row_a')),
      );
      expect((box.decoration as BoxDecoration).color, tokens.card);
    });
  }

  // 6. Icon-only buttons name themselves.

  testWidgets('every icon-only button carries a tooltip', (tester) async {
    await pumpAt(tester, const ThingList(items: threeThings));

    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.tooltip, isNotNull, reason: 'an icon alone says nothing');
    }
  });

  // 7. Long text and many items do not overflow.

  testBothViewports('survives a long name and a long list', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      ThingList(
        items: [
          for (var i = 0; i < 200; i++) Thing(id: '$i', name: 'Vacation ' * 30),
        ],
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });
}

// ---------------------------------------------------------------------------
// The widget under test. Delete this and import your own instead.
// ---------------------------------------------------------------------------

/// One row's worth of data. Value types are immutable and compare by value.
class Thing {
  /// Creates a thing.
  const Thing({required this.id, required this.name});

  /// Stable identity, and the suffix of every key this row emits.
  final String id;

  /// What the row shows.
  final String name;
}

/// A list of things: data in, callbacks out.
///
/// Key prefixes:
/// - `thing_row_<id>` for the row itself
/// - `thing_delete_<id>` for the row's delete button
class ThingList extends StatelessWidget {
  /// Creates a thing list.
  const ThingList({
    super.key,
    required this.items,
    this.selectedIds = const {},
    this.isLoading = false,
    this.error,
    this.onSelect,
    this.onDelete,
  });

  /// The rows to render, in order.
  final List<Thing> items;

  /// The ids currently selected.
  final Set<String> selectedIds;

  /// Whether the caller is still fetching. The widget never decides this.
  final bool isLoading;

  /// The caller's error sentence, rendered as given. Null when there is none.
  final String? error;

  /// Fires with the id of the row the user tapped.
  final ValueChanged<String>? onSelect;

  /// Fires with the id of the row whose delete button was tapped. Null
  /// disables every delete button.
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<QuarkTokens>()!;
    if (isLoading) {
      return const Center(child: QuarkLoader());
    }
    if (error != null) {
      return Center(child: Text(error!));
    }
    if (items.isEmpty) {
      return const Center(child: Text('Nothing here yet'));
    }
    return ListView(
      children: [
        for (final thing in items)
          DecoratedBox(
            key: ValueKey('thing_row_${thing.id}'),
            decoration: BoxDecoration(color: tokens.card),
            child: Row(
              children: [
                if (selectedIds.contains(thing.id)) const Icon(Icons.check),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onSelect?.call(thing.id),
                    child: Text(thing.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
                IconButton(
                  key: ValueKey('thing_delete_${thing.id}'),
                  tooltip: 'Delete ${thing.name}',
                  icon: const Icon(Icons.delete),
                  onPressed: onDelete == null
                      ? null
                      : () => onDelete!(thing.id),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
