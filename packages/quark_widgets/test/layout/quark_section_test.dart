// The titled block: heading, actions, content.
//
// The narrow cases guard the heading row, which is where a title and three
// buttons used to overflow before the actions went through a toolbar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('renders the title above the content', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkSection(
        title: 'Backend hosts',
        child: Text('two hosts configured'),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Backend hosts'), findsOneWidget);
    expect(
      tester.getRect(find.text('two hosts configured')).top,
      greaterThan(tester.getRect(find.text('Backend hosts')).top),
    );
  });

  testBothViewports('renders the actions the caller handed it', (
    tester,
    size,
  ) async {
    final tapped = <String>[];
    await pumpAt(
      tester,
      QuarkSection(
        title: 'Backend hosts',
        actions: [
          IconButton(
            key: const ValueKey('host_add'),
            icon: const Icon(Icons.add),
            tooltip: 'Add a host',
            onPressed: () => tapped.add('add'),
          ),
        ],
        child: const Text('two hosts configured'),
      ),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('host_add')));
    await tester.pump();

    expect(tapped, ['add']);
  });

  testBothViewports('renders a glyph only when it is given one', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkSection(title: 'Backend hosts', child: Text('content')),
      size: size,
    );
    expect(find.byType(Icon), findsNothing);

    await pumpAt(
      tester,
      const QuarkSection(
        title: 'Software Bill of Materials',
        icon: Icons.info_outline,
        child: Text('content'),
      ),
      size: size,
    );
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testBothViewports('emits a key built from the title', (tester, size) async {
    await pumpAt(
      tester,
      const QuarkSection(title: 'Help & Support', child: Text('content')),
      size: size,
    );

    expect(find.byKey(const ValueKey('section_help_support')), findsOneWidget);
  });

  test('the slug is lowercase, underscored, and untrimmed of nothing else', () {
    expect(QuarkSection.slug('Help & Support'), 'help_support');
    expect(QuarkSection.slug('Backend hosts'), 'backend_hosts');
    expect(QuarkSection.slug('SBOM (v2)'), 'sbom_v2');
  });

  testWidgets('narrow: the actions drop under the heading on one row', (
    tester,
  ) async {
    const title = 'A section with a heading long enough to crowd its actions';
    await pumpAt(
      tester,
      QuarkSection(
        title: title,
        actions: [
          for (final label in const ['Refresh', 'Add', 'Remove everything'])
            FilledButton(
              key: ValueKey('section_action_$label'),
              onPressed: () {},
              child: Text(label),
            ),
        ],
        child: const Text('content'),
      ),
      size: narrowViewport,
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(QuarkToolbar), findsOneWidget);
    for (final label in const ['Refresh', 'Add', 'Remove everything']) {
      expect(find.byKey(ValueKey('section_action_$label')), findsOneWidget);
    }
    final first = tester.getRect(
      find.byKey(const ValueKey('section_action_Refresh')),
    );
    final last = tester.getRect(
      find.byKey(const ValueKey('section_action_Remove everything')),
    );
    expect(first.top, greaterThan(tester.getRect(find.text(title)).bottom - 1));
    expect(last.top, first.top, reason: 'a toolbar is one row high (#2770)');
  });

  testWidgets('a small action set leaves the heading its own width', (
    tester,
  ) async {
    await pumpAt(
      tester,
      QuarkSection(
        title: 'Backend hosts',
        actions: [
          IconButton(
            key: const ValueKey('host_add'),
            icon: const Icon(Icons.add),
            tooltip: 'Add a host',
            onPressed: () {},
          ),
        ],
        child: const Text('content'),
      ),
      size: wideViewport,
    );

    // One small button must not cost the heading half the row, which is what
    // a Row of two flexible children does.
    final title = tester.getRect(find.text('Backend hosts'));
    final action = tester.getRect(find.byKey(const ValueKey('host_add')));
    expect(title.right, lessThan(wideViewport.width / 4));
    expect(action.left, greaterThan(wideViewport.width / 2));
  });

  testWidgets('every icon-only action carries a tooltip', (tester) async {
    await pumpAt(
      tester,
      QuarkSection(
        title: 'Backend hosts',
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add a host',
            onPressed: () {},
          ),
        ],
        child: const Text('content'),
      ),
    );

    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.tooltip, isNotNull, reason: 'an icon alone says nothing');
    }
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the gap under the heading comes from the tokens', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const QuarkSection(title: 'Backend hosts', child: Text('content')),
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      final gaps = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(QuarkSection),
              matching: find.byType(SizedBox),
            ),
          )
          .where((box) => box.height != null);
      expect(gaps.first.height, tokens.spacingSm);
    });
  }

  testBothViewports('survives a very long title', (tester, size) async {
    await pumpAt(
      tester,
      QuarkSection(
        title: 'Software Bill of Materials ' * 20,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add',
            onPressed: () {},
          ),
        ],
        child: const Text('content'),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });
}
