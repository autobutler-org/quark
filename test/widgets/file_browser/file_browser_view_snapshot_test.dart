import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark_widgets/quark_widgets.dart';

FileNode _node(String name) => FileNode(
  name: name,
  size: 2048,
  isDir: false,
  deviceName: 'Attic',
  devicePath: '/dev/sda',
  deviceSerial: '',
  dirPath: name,
);

final _kept = [_node('budget.csv'), _node('notes.txt')];

/// #1781: a listing the page already holds — the last one fetched, or one
/// read off disk at a cold launch — is on screen while the Quark has not
/// answered, and stays there when it cannot be reached.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Future<List<FileNode>> filesFuture,
    List<FileNode>? initialData,
    bool isInitialLoad = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FileBrowserView(
          filesFuture: filesFuture,
          initialData: initialData,
          isInitialLoad: isInitialLoad,
          currentPath: '',
          onFileMenuAction: (_, _) async {},
          onOpenDirectory: (_) {},
          isGridView: false,
          errorBuilder: (_, error) => Text('Route error: $error'),
        ),
      ),
    ),
  );

  void expectKeptRows() {
    expect(find.text('budget.csv'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(find.textContaining('Route error'), findsNothing);
  }

  testWidgets('a kept listing shows during the initial load', (tester) async {
    final pending = Completer<List<FileNode>>();
    await pump(
      tester,
      filesFuture: pending.future,
      initialData: _kept,
      isInitialLoad: true,
    );
    await tester.pump();

    expectKeptRows();
  });

  testWidgets('a kept listing that arrives after the first frame shows', (
    tester,
  ) async {
    final pending = Completer<List<FileNode>>();
    await pump(tester, filesFuture: pending.future, isInitialLoad: true);
    await tester.pump();
    expect(find.byType(QuarkLoader), findsOneWidget);

    await pump(
      tester,
      filesFuture: pending.future,
      initialData: _kept,
      isInitialLoad: true,
    );
    await tester.pump();

    expectKeptRows();
  });

  testWidgets('a kept listing stays when the Quark cannot be reached', (
    tester,
  ) async {
    final listing = Completer<List<FileNode>>();
    await pump(tester, filesFuture: listing.future, initialData: _kept);
    listing.completeError(http.ClientException('Connection refused'));
    await tester.pump();
    await tester.pump();

    expectKeptRows();
  });

  testWidgets('an error the Quark answered with replaces a kept listing', (
    tester,
  ) async {
    final listing = Completer<List<FileNode>>();
    await pump(tester, filesFuture: listing.future, initialData: _kept);
    listing.completeError(const ApiException(404, 'list files'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Route error'), findsOneWidget);
    expect(find.text('budget.csv'), findsNothing);
  });

  testWidgets('with nothing kept, the initial load is a loader', (
    tester,
  ) async {
    final pending = Completer<List<FileNode>>();
    await pump(tester, filesFuture: pending.future, isInitialLoad: true);
    await tester.pump();

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.text('budget.csv'), findsNothing);
  });

  testWidgets('with nothing kept, an unreachable Quark is still an error', (
    tester,
  ) async {
    final listing = Completer<List<FileNode>>();
    await pump(tester, filesFuture: listing.future);
    listing.completeError(http.ClientException('Connection refused'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Route error'), findsOneWidget);
  });

  testWidgets('a fresh listing replaces the kept one', (tester) async {
    final listing = Completer<List<FileNode>>();
    await pump(tester, filesFuture: listing.future, initialData: _kept);
    listing.complete([_node('fresh.txt')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('fresh.txt'), findsOneWidget);
    expect(find.text('budget.csv'), findsNothing);
  });
}
