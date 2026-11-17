import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  final log = <String>[];

  Future<void> pumpSheet(
    WidgetTester tester, {
    Size size = wideViewport,
    bool ascending = true,
    bool isGridView = false,
    bool? isGroupedByDevice,
    List<FileDeviceChoice> devices = const [],
  }) {
    log.clear();
    return pumpInSheet(
      tester,
      FileSortViewSheet(
        sortOptions: const ['Name', 'Modified', 'Size'],
        selectedSort: 'Modified',
        ascending: ascending,
        isGridView: isGridView,
        isGroupedByDevice: isGroupedByDevice,
        devices: devices,
        onSortSelected: (s) => log.add('sort $s'),
        onAscendingChanged: (a) => log.add('ascending $a'),
        onGridViewChanged: (g) => log.add('grid $g'),
        onGroupedByDeviceChanged: isGroupedByDevice == null
            ? null
            : (g) => log.add('grouped $g'),
        onDeviceToggled: (id) => log.add('device $id'),
      ),
      size: size,
    );
  }

  testBothViewports('offers every sort, both orders and both layouts', (
    tester,
    size,
  ) async {
    await pumpSheet(tester, size: size);

    for (final key in [
      'file_sort_view_sort_name',
      'file_sort_view_sort_modified',
      'file_sort_view_sort_size',
      'file_sort_view_ascending',
      'file_sort_view_descending',
      'file_sort_view_list',
      'file_sort_view_grid',
    ]) {
      final row = find.byKey(ValueKey(key));
      expect(row, findsOneWidget, reason: key);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    }
    expect(find.byKey(const ValueKey('file_sort_view_grouping')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marks what is chosen', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSheet(tester, ascending: false, isGridView: true);

    void expectSelected(String key, bool selected) => expect(
      tester.getSemantics(find.byKey(ValueKey(key))),
      isSemantics(hasSelectedState: true, isSelected: selected),
      reason: key,
    );

    expectSelected('file_sort_view_sort_modified', true);
    expectSelected('file_sort_view_sort_name', false);
    expectSelected('file_sort_view_descending', true);
    expectSelected('file_sort_view_ascending', false);
    expectSelected('file_sort_view_grid', true);
    expectSelected('file_sort_view_list', false);
    handle.dispose();
  });

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    await pumpSheet(tester, size: size, isGroupedByDevice: true);

    await expectTapTargetGuidelines(tester);
  });

  testWidgets('hands back each choice', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.byKey(const ValueKey('file_sort_view_sort_size')));
    await tester.tap(find.byKey(const ValueKey('file_sort_view_descending')));
    await tester.tap(find.byKey(const ValueKey('file_sort_view_grid')));
    await tester.pump();

    expect(log, ['sort Size', 'ascending false', 'grid true']);
  });

  testWidgets('offers grouping and devices only when given them', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      isGroupedByDevice: false,
      devices: const [
        FileDeviceChoice(id: 'a', label: 'Internal', selected: true),
        FileDeviceChoice(id: 'b', label: 'USB drive', selected: false),
      ],
    );

    for (final key in ['file_sort_view_grouping', 'file_sort_view_device_b']) {
      // The sheet scrolls; the drives sit at its foot.
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
    }
    await tester.pump();

    expect(log, ['grouped true', 'device b']);
  });
}
