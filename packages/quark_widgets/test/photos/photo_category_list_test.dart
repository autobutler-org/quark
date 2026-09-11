import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _categories = [
  PhotoCategoryEntry(
    id: 'all',
    label: 'All',
    count: 12,
    icon: QuarkIcons.photo_library,
  ),
  PhotoCategoryEntry(
    id: 'quark',
    label: 'Quark',
    count: 10,
    icon: QuarkIcons.cloud,
  ),
  PhotoCategoryEntry(
    id: 'favorites',
    label: 'Favorites',
    count: 2,
    icon: QuarkIcons.star_rounded,
  ),
];

void main() {
  Future<void> pumpList(
    WidgetTester tester, {
    Size size = wideViewport,
    bool expanded = false,
    List<String>? events,
  }) {
    return pumpAt(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280,
          child: PhotoCategoryList(
            categories: _categories,
            selectedId: 'quark',
            expanded: expanded,
            onToggleExpanded: () => events?.add('toggle'),
            onSelected: (id) => events?.add('select:$id'),
          ),
        ),
      ),
      size: size,
    );
  }

  testBothViewports('summarizes the selected category when collapsed', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpList(tester, size: size, events: events);

    expect(find.text('Showing'), findsOneWidget);
    expect(find.text('Quark: 10'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_category_all')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('photo_category_toggle')));
    expect(events, ['toggle']);
  });

  testBothViewports('lists and checks every category when expanded', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpList(tester, size: size, expanded: true, events: events);

    expect(tester.takeException(), isNull);
    expect(find.text('All: 12'), findsOneWidget);
    expect(find.text('Favorites: 2'), findsOneWidget);
    expect(find.byIcon(QuarkIcons.check), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('photo_category_favorites')));
    expect(events, ['select:favorites']);
  });
}
