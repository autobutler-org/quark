import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/src/core/quark_detail_row.dart';

import '../support/pump.dart';

/// The label-over-value row behind the vault entry details and the drive
/// health readings.
void main() {
  testBothViewports('prints the label over the value', (tester, size) async {
    await pumpAt(
      tester,
      const QuarkDetailRow(
        key: ValueKey('drive_health_row_hours'),
        label: 'Power-on hours',
        value: '1,200 hours',
      ),
      size: size,
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('drive_health_row_hours')),
        matching: find.text('1,200 hours'),
      ),
      findsOneWidget,
    );
    expect(find.text('Power-on hours'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('a selectable value keeps its actions beside it', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkDetailRow(
        label: 'Username',
        value: 'a-very-long-username-' * 8,
        selectable: true,
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(QuarkIcons.content_copy),
          ),
        ],
      ),
      size: size,
    );

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(IconButton), findsOneWidget);
    expect(
      tester.getSize(find.byType(SelectableText)).height,
      greaterThanOrEqualTo(kMinInteractiveDimension),
    );
    expect(tester.takeException(), isNull);
  });
}
