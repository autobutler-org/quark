import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The duplicates view (#1666). The part worth guarding is that it is always
/// clear which copy is kept, and that a group can never lose every copy.
void main() {
  const exact = DuplicateGroupItem(
    id: 'g1',
    isExact: true,
    photos: [
      DuplicatePhotoItem(id: 'a', name: 'beach.jpg', location: 'Camera'),
      DuplicatePhotoItem(id: 'b', name: 'beach.jpg', location: 'Backups/2024'),
    ],
  );
  const near = DuplicateGroupItem(
    id: 'g2',
    isExact: false,
    photos: [
      DuplicatePhotoItem(id: 'c', name: 'dog.jpg', location: 'Camera'),
      DuplicatePhotoItem(id: 'd', name: 'dog edit.jpg', location: 'Edits'),
      DuplicatePhotoItem(id: 'e', name: 'dog small.jpg', location: 'Edits'),
    ],
  );
  const groups = [exact, near];

  Future<void> pumpList(
    WidgetTester tester, {
    Size size = wideViewport,
    Brightness brightness = Brightness.dark,
    List<DuplicateGroupItem> groups = groups,
    Set<String> selectedIds = const {},
    bool isLoading = false,
    bool isDeleting = false,
    String? error,
    List<String>? events,
  }) => pumpAt(
    tester,
    DuplicateGroupList(
      groups: groups,
      selectedIds: selectedIds,
      isLoading: isLoading,
      isDeleting: isDeleting,
      error: error,
      thumbnailBuilder: (context, photo) =>
          const ColoredBox(color: Colors.teal),
      onToggle: (id) => events?.add('toggle:$id'),
      onDeleteSelected: () => events?.add('delete'),
    ),
    size: size,
    brightness: brightness,
  );

  FilledButton deleteButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.byKey(const ValueKey('duplicates_delete')),
  );

  testBothViewports('shows a loader while loading and nothing else', (
    tester,
    size,
  ) async {
    await pumpList(tester, size: size, groups: const [], isLoading: true);

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.text('No duplicates found'), findsNothing);
  });

  testBothViewports('renders the error the caller handed it', (
    tester,
    size,
  ) async {
    await pumpList(tester, size: size, error: "Couldn't find duplicates.");

    expect(find.text("Couldn't find duplicates."), findsOneWidget);
    expect(find.byKey(const ValueKey('duplicate_group_g1')), findsNothing);
  });

  testBothViewports('says so when there are none', (tester, size) async {
    await pumpList(tester, size: size, groups: const []);

    expect(find.text('No duplicates found'), findsOneWidget);
    expect(find.byKey(const ValueKey('duplicates_delete')), findsNothing);
  });

  testBothViewports('names each group and every copy, with where it is', (
    tester,
    size,
  ) async {
    await pumpList(tester, size: size);

    expect(tester.takeException(), isNull);
    expect(find.text('Identical copies · 2'), findsOneWidget);
    expect(find.text('Similar photos · 3'), findsOneWidget);
    expect(find.text('Backups/2024'), findsOneWidget);
    for (final group in groups) {
      expect(find.byKey(ValueKey('duplicate_group_${group.id}')), findsOne);
      for (final photo in group.photos) {
        expect(find.byKey(ValueKey('duplicate_photo_${photo.id}')), findsOne);
      }
    }
  });

  testBothViewports('marks every copy Keep until one is marked Delete', (
    tester,
    size,
  ) async {
    await pumpList(tester, size: size, selectedIds: const {'b'});

    expect(find.text('Keep'), findsNWidgets(4));
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Delete 1 photo'), findsOneWidget);
  });

  testBothViewports('reports taps and the delete, once each', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpList(
      tester,
      size: size,
      selectedIds: const {'b'},
      events: events,
    );

    await tester.tap(find.byKey(const ValueKey('duplicate_photo_d')));
    await tester.tap(find.byKey(const ValueKey('duplicate_photo_b')));
    await tester.tap(find.byKey(const ValueKey('duplicates_delete')));
    await tester.pump();

    expect(events, ['toggle:d', 'toggle:b', 'delete']);
  });

  testWidgets('a group cannot lose its last copy', (tester) async {
    final events = <String>[];
    await pumpList(tester, selectedIds: const {'b'}, events: events);

    // a is the only copy g1 still keeps.
    await tester.tap(find.byKey(const ValueKey('duplicate_photo_a')));
    await tester.pump();

    expect(events, isEmpty);
  });

  testWidgets('nothing marked means nothing to delete', (tester) async {
    await pumpList(tester);

    expect(deleteButton(tester).onPressed, isNull);
    expect(find.text('Tap a copy to mark it for deletion'), findsOneWidget);
  });

  testWidgets('a running delete busies the button', (tester) async {
    await pumpList(tester, selectedIds: const {'b'}, isDeleting: true);

    expect(deleteButton(tester).onPressed, isNull);
    expect(find.byType(QuarkLoader), findsOneWidget);
  });

  testBothViewports('survives long names and many groups', (
    tester,
    size,
  ) async {
    await pumpList(
      tester,
      size: size,
      groups: [
        for (var g = 0; g < 30; g++)
          DuplicateGroupItem(
            id: 'g$g',
            isExact: g.isEven,
            photos: [
              for (var p = 0; p < 4; p++)
                DuplicatePhotoItem(
                  id: '$g-$p',
                  name: 'Vacation ' * 20,
                  location: 'Somewhere ' * 20,
                ),
            ],
          ),
      ],
    );

    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: Keep and Delete come from the tokens', (tester) async {
      await pumpList(tester, brightness: brightness, selectedIds: const {'b'});

      Color? badge(String text) {
        final box = tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.text(text).first,
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        return (box.decoration as BoxDecoration).color;
      }

      expect(badge('Delete'), tokens.error);
      expect(badge('Keep'), tokens.primary);
    });
  }
}
