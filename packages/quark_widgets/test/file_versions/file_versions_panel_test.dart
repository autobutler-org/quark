import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The version history panel: its loading, empty, error and list states, the
/// Preview and Restore callbacks, and the busy state that keeps two restores
/// from overlapping.
void main() {
  final versions = [
    FileVersionItem(
      id: 'v3',
      createdAt: DateTime(2026, 10, 11, 15, 4),
      sizeLabel: '2.0 KB',
      author: 'You',
      label: 'Before restore',
    ),
    FileVersionItem(
      id: 'v2',
      createdAt: DateTime(2026, 10, 10, 9, 30),
      sizeLabel: '1.5 KB',
      author: 'alice',
      label: 'Final draft',
      isNamed: true,
    ),
    FileVersionItem(
      id: 'v1',
      createdAt: DateTime(2026, 10, 9, 8),
      sizeLabel: '900 B',
    ),
  ];

  Future<void> pumpPanel(
    WidgetTester tester, {
    Size size = wideViewport,
    Brightness brightness = Brightness.dark,
    List<FileVersionItem>? items,
    bool isLoading = false,
    String? error,
    String? notice,
    String? busyId,
    ValueChanged<String>? onPreview,
    ValueChanged<String>? onRestore,
    VoidCallback? onRefresh,
  }) => pumpInSheet(
    tester,
    FileVersionsPanel(
      versions: items ?? versions,
      isLoading: isLoading,
      error: error,
      notice: notice,
      busyId: busyId,
      onPreview: onPreview,
      onRestore: onRestore,
      onRefresh: onRefresh,
    ),
    size: size,
    brightness: brightness,
  );

  IconButton button(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(ValueKey(key)));

  testBothViewports('shows a loader while the first load is out', (
    tester,
    size,
  ) async {
    await pumpPanel(tester, size: size, items: const [], isLoading: true);

    expect(find.byKey(const ValueKey('file_versions_panel')), findsOneWidget);
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.textContaining('No earlier versions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('says so when the file has no versions', (
    tester,
    size,
  ) async {
    await pumpPanel(tester, size: size, items: const []);

    expect(find.textContaining('No earlier versions'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the error the caller handed it', (tester) async {
    await pumpPanel(
      tester,
      items: const [],
      error: "Couldn't load the versions.",
    );

    expect(find.text("Couldn't load the versions."), findsOneWidget);
    expect(
      find.textContaining('No earlier versions'),
      findsNothing,
      reason: 'a failed load is not an empty history',
    );
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('lists each version with its time, size and author', (
    tester,
    size,
  ) async {
    await pumpPanel(tester, size: size, onPreview: (_) {}, onRestore: (_) {});

    for (final version in versions) {
      expect(
        find.byKey(ValueKey('file_version_tile_${version.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('file_version_preview_${version.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('file_version_restore_${version.id}')),
        findsOneWidget,
      );
    }
    expect(find.text('Oct 11, 2026, 3:04 PM'), findsOneWidget);
    expect(find.text('Before restore · 2.0 KB · You'), findsOneWidget);
    expect(find.text('Final draft · 1.5 KB · alice'), findsOneWidget);
    expect(
      find.text('Automatic · 900 B'),
      findsOneWidget,
      reason: 'an author nobody could name is left out, not half-labeled',
    );
    expect(find.byType(QuarkLoader), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the rows on screen through a refresh', (tester) async {
    await pumpPanel(tester, isLoading: true, error: 'Offline.');

    expect(find.byKey(const ValueKey('file_version_tile_v2')), findsOneWidget);
    expect(find.text('Offline.'), findsOneWidget);
  });

  testWidgets('reports the version whose button was tapped', (tester) async {
    final events = <String>[];
    await pumpPanel(
      tester,
      onPreview: (id) => events.add('preview $id'),
      onRestore: (id) => events.add('restore $id'),
      onRefresh: () => events.add('refresh'),
    );

    await tester.tap(find.byKey(const ValueKey('file_version_preview_v2')));
    await tester.tap(find.byKey(const ValueKey('file_version_restore_v1')));
    await tester.tap(find.byKey(const ValueKey('refresh_button')));
    await tester.pump();

    expect(events, ['preview v2', 'restore v1', 'refresh']);
  });

  testWidgets('shows the busy row loading and dims the others', (tester) async {
    final events = <String>[];
    await pumpPanel(
      tester,
      busyId: 'v2',
      onPreview: events.add,
      onRestore: events.add,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byKey(const ValueKey('file_version_restore_v2')), findsNothing);
    expect(button(tester, 'file_version_restore_v1').onPressed, isNull);
    expect(button(tester, 'file_version_preview_v3').onPressed, isNull);
    await tester.tap(
      find.byKey(const ValueKey('file_version_restore_v1')),
      warnIfMissed: false,
    );
    expect(events, isEmpty);
  });

  testWidgets('dims an action the caller does not offer', (tester) async {
    await pumpPanel(tester, onPreview: (_) {});

    expect(button(tester, 'file_version_preview_v1').onPressed, isNotNull);
    expect(button(tester, 'file_version_restore_v1').onPressed, isNull);
    expect(
      find.byKey(const ValueKey('refresh_button')),
      findsNothing,
      reason: 'no onRefresh, no button',
    );
  });

  testWidgets('every icon-only button carries a tooltip', (tester) async {
    await pumpPanel(tester, onPreview: (_) {}, onRestore: (_) {});

    for (final iconButton in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(iconButton.tooltip, isNotNull, reason: 'an icon says nothing');
    }
  });

  testBothViewports('names each button after its version', (
    tester,
    size,
  ) async {
    await pumpPanel(tester, size: size, onPreview: (_) {}, onRestore: (_) {});

    String tooltip(String key) => button(tester, key).tooltip!;
    expect(
      tooltip('file_version_restore_v2'),
      startsWith('Restore Final draft, '),
    );
    expect(
      tooltip('file_version_preview_v2'),
      startsWith('Preview Final draft, '),
    );
    expect(
      tooltip('file_version_restore_v1'),
      startsWith('Restore version from '),
    );
    final names = {
      for (final version in versions)
        tooltip('file_version_restore_${version.id}'),
    };
    expect(
      names,
      hasLength(versions.length),
      reason: 'no two rows sound alike',
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('announces the error and the notice', (tester, size) async {
    await pumpPanel(
      tester,
      size: size,
      error: 'Read-only.',
      notice: 'Restored.',
    );

    for (final text in ['Read-only.', 'Restored.']) {
      final live = find.ancestor(
        of: find.text(text),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      );
      expect(live, findsOneWidget, reason: '$text is a live region');
    }
    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    testWidgets('$label: the error and the notice take token colors', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        brightness: brightness,
        error: 'Read-only.',
        notice: 'Restored.',
      );

      final tokens = QuarkThemeColor.classic.tokensFor(brightness);
      expect(
        tester.widget<Text>(find.text('Read-only.')).style?.color,
        tokens.error,
      );
      expect(
        tester.widget<Text>(find.text('Restored.')).style?.color,
        tokens.success,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testBothViewports('survives long labels and a long history', (
    tester,
    size,
  ) async {
    await pumpPanel(
      tester,
      size: size,
      items: [
        for (var i = 0; i < 60; i++)
          FileVersionItem(
            id: '$i',
            createdAt: DateTime(2026, 10, 11),
            sizeLabel: '1023.9 MB',
            author: 'a-username-that-goes-on-for-far-too-long ' * 3,
            label: 'A label nobody would type by hand ' * 4,
            isNamed: true,
          ),
      ],
      onPreview: (_) {},
      onRestore: (_) {},
      onRefresh: () {},
    );

    expect(tester.takeException(), isNull);
  });

  testLargeText('lays out without clipping', (tester, size) async {
    await pumpPanel(tester, size: size, onPreview: (_) {}, onRestore: (_) {});

    expect(tester.takeException(), isNull);
  });
}
