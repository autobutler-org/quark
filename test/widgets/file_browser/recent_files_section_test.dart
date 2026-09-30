import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/recent_files_section.dart';
import 'package:quark/widgets/file_browser/recent_files_section/recent_file_chip.dart';

import '../../support/tap_targets.dart';

FileNode _file(String name) => FileNode(
  name: name,
  size: 1,
  isDir: false,
  deviceName: 'disk',
  devicePath: '/mnt/disk',
  deviceSerial: 'serial',
  dirPath: '/$name',
);

void main() {
  late List<Completer<List<FileNode>>> fetches;

  Future<List<FileNode>> fakeGetRecentFiles({
    int limit = 20,
    List<String>? serials,
  }) {
    final completer = Completer<List<FileNode>>();
    fetches.add(completer);
    return completer.future;
  }

  Future<void> pumpSection(WidgetTester tester, int refreshToken) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentFilesSection(
            refreshToken: refreshToken,
            getRecentFiles: fakeGetRecentFiles,
            onOpenFile: (_) {},
            onNavigateToFolder: (_) {},
          ),
        ),
      ),
    );
  }

  setUp(() => fetches = []);

  // #2446: a refresh used to remount the strip, which rendered nothing until
  // the new fetch returned.
  testWidgets('keeps the strip visible while a refresh is pending', (
    tester,
  ) async {
    await pumpSection(tester, 0);
    fetches.single.complete([_file('a.txt')]);
    await tester.pump();
    expect(find.text('Recently uploaded'), findsOneWidget);

    await pumpSection(tester, 1);
    expect(fetches, hasLength(2));
    expect(find.text('Recently uploaded'), findsOneWidget);
    expect(find.text('a.txt'), findsOneWidget);
  });

  // #2080: a file deleted since the last fetch drops out after a refresh.
  testWidgets('shows the new list once the refresh lands', (tester) async {
    await pumpSection(tester, 0);
    fetches.single.complete([_file('a.txt'), _file('b.txt')]);
    await tester.pump();

    await pumpSection(tester, 1);
    fetches.last.complete([_file('b.txt')]);
    await tester.pumpAndSettle();
    expect(find.text('a.txt'), findsNothing);
    expect(find.text('b.txt'), findsOneWidget);
  });

  testWidgets('does not refetch when the token is unchanged', (tester) async {
    await pumpSection(tester, 0);
    await pumpSection(tester, 0);
    expect(fetches, hasLength(1));
  });

  for (final (label, size) in [
    ('narrow', narrowViewport),
    ('wide', wideViewport),
  ]) {
    testWidgets('each chip and its folder badge are 48 pixel targets '
        '($label, #2605)', (tester) async {
      setViewport(tester, size);
      await pumpSection(tester, 0);
      fetches.single.complete([_file('a.txt'), _file('b.txt')]);
      await tester.pump();

      await expectTapTargetsMeetGuideline(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the strip survives 200% text on a phone (#2606)', (
    tester,
  ) async {
    setViewport(tester, narrowViewport);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: app!,
        ),
        home: Scaffold(
          body: RecentFilesSection(
            getRecentFiles: fakeGetRecentFiles,
            onOpenFile: (_) {},
            onNavigateToFolder: (_) {},
          ),
        ),
      ),
    );
    fetches.single.complete([_file('a.txt'), _file('b.txt')]);
    await tester.pump();

    expect(tester.takeException(), isNull);
    final chip = tester.getRect(find.byType(RecentFileChip).first);
    for (final line in ['a.txt', 'disk']) {
      final text = tester.getRect(find.text(line).first);
      expect(text.bottom, lessThanOrEqualTo(chip.bottom), reason: line);
    }
  });
}
