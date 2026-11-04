import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  // #3937 extends the #3645 guard: a tooltip on the tag must not become the
  // name of a larger ancestor. The tag already paints its name.
  testBothViewports('never lets its tooltip name a larger ancestor', (
    tester,
    size,
  ) async {
    final handle = tester.ensureSemantics();
    const tooltip = 'Family archive drive';
    const key = ValueKey('device_tag_A1B2');
    await pumpAt(
      tester,
      const Center(
        child: SizedBox(
          width: 320,
          height: 200,
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Trip 2026'),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DeviceTag(
                    key: key,
                    label: 'Family',
                    tooltip: tooltip,
                    color: Color(0xFF0EA5E9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      size: size,
    );

    final carriers = find.semantics
        .byPredicate((node) {
          return node.label.contains(tooltip) || node.tooltip.contains(tooltip);
        })
        .evaluate()
        .toList();
    expect(carriers, isEmpty, reason: 'the tooltip became a name');

    final named = find.semantics
        .byPredicate((node) => node.label.contains('Trip 2026'))
        .evaluate()
        .toList();
    expect(named, hasLength(1));
    final node = named.single;
    expect(node.label, startsWith('Trip 2026'));
    expect(node.label, contains('Family'));
    expect(node.tooltip, isEmpty);
    expect(node.rect.width, greaterThan(tester.getSize(find.byKey(key)).width));
    handle.dispose();
  });

  // A squeezed tag paints an ellipsis. The accessible name is still the
  // whole device, and it stays on the tag rather than a page-sized ancestor.
  testBothViewports('reads the full name when the label is cut short', (
    tester,
    size,
  ) async {
    final handle = tester.ensureSemantics();
    const label = 'Family archive drive';
    const key = ValueKey('device_tag_A1B2');
    await pumpAt(
      tester,
      const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 80,
          child: DeviceTag(key: key, label: label, color: Color(0xFF10B981)),
        ),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
    expect(paragraph.didExceedMaxLines, isTrue);

    final carriers = find.semantics
        .byPredicate((node) {
          return node.label.contains(label) || node.tooltip.contains(label);
        })
        .evaluate()
        .toList();
    expect(carriers, hasLength(1), reason: label);
    final node = carriers.single;
    expect(node.label, label);
    expect(node.tooltip, isEmpty);
    final tagSize = tester.getSize(find.byKey(key));
    expect(node.rect.width, lessThanOrEqualTo(tagSize.width));
    expect(node.rect.height, lessThanOrEqualTo(tagSize.height));
    handle.dispose();
  });
}
