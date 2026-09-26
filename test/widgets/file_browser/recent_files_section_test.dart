import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/recent_files_section.dart';

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
}
