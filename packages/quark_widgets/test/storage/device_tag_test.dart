import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('cuts a long label short in a tight row', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      Center(
        child: SizedBox(
          width: 120,
          child: Row(
            children: [
              const Text('file.txt'),
              Flexible(
                child: DeviceTag(
                  key: const ValueKey('device_tag_A1B2'),
                  label: 'A very long external drive name',
                  color: QuarkTokens.dark.eventColors.first,
                ),
              ),
            ],
          ),
        ),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('device_tag_A1B2')), findsOneWidget);
    final text = tester.widget<Text>(
      find.text('A very long external drive name'),
    );
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(
      tester.getSize(find.byKey(const ValueKey('device_tag_A1B2'))).width,
      lessThan(120),
    );
    expectNoClippedText(tester);
  });

  testWidgets('long-press shows the tooltip, defaulting to the label', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DeviceTag(label: 'Internal', color: Color(0xFF0EA5E9)),
            DeviceTag(
              label: 'USB Backup',
              color: Color(0xFF10B981),
              tooltip: 'USB Backup (A1B2)',
            ),
          ],
        ),
      ),
    );

    expect(
      tester.widget<Tooltip>(find.byType(Tooltip).first).message,
      'Internal',
    );
    await tester.longPress(find.text('USB Backup'));
    await tester.pumpAndSettle();
    expect(find.text('USB Backup (A1B2)'), findsOneWidget);
  });

  testWidgets('colorFor is stable FNV-1a over the event colors', (
    tester,
  ) async {
    late BuildContext context;
    await pumpAt(
      tester,
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );

    final colors = QuarkTokens.of(context).eventColors;
    // Reference FNV-1a 32-bit hashes, mod 6: '' -> 1, 'A' -> 0, 'A1B2' -> 5.
    expect(DeviceTag.colorFor(context, ''), colors[1]);
    expect(DeviceTag.colorFor(context, 'A'), colors[0]);
    expect(DeviceTag.colorFor(context, 'A1B2'), colors[5]);
    expect(
      DeviceTag.colorFor(context, 'A1B2'),
      DeviceTag.colorFor(context, 'A1B2'),
    );
    expect(
      DeviceTag.colorFor(context, ''),
      isNot(DeviceTag.colorFor(context, 'A')),
    );
  });
}
