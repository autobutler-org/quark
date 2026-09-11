import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';

void main() {
  Future<void> pumpFileBrowserView(
    WidgetTester tester, {
    required Future<List<FileNode>> filesFuture,
    bool isInitialLoad = false,
    Widget Function(BuildContext context, Object error)? errorBuilder,
    WidgetBuilder? loadingBuilder,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileBrowserView(
            filesFuture: filesFuture,
            isInitialLoad: isInitialLoad,
            currentPath: '/Documents',
            onFileMenuAction: (_, _) async {},
            onOpenDirectory: (_) {},
            isGridView: false,
            errorBuilder: errorBuilder,
            loadingBuilder: loadingBuilder,
          ),
        ),
      ),
    );
  }

  testWidgets('uses the custom loading builder during initial loads', (
    WidgetTester tester,
  ) async {
    await pumpFileBrowserView(
      tester,
      filesFuture: Future.value(const <FileNode>[]),
      isInitialLoad: true,
      loadingBuilder: (_) => const Text('Opening /files/Documents'),
    );

    expect(find.text('Opening /files/Documents'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('uses the custom error builder for failed folder loads', (
    WidgetTester tester,
  ) async {
    final completer = Completer<List<FileNode>>();
    await pumpFileBrowserView(
      tester,
      filesFuture: completer.future,
      errorBuilder: (_, error) => Text('Route error: $error'),
    );
    completer.completeError(Exception('folder not found'));
    await tester.pumpAndSettle();

    expect(
      find.text('Route error: Exception: folder not found'),
      findsOneWidget,
    );
    expect(find.text('Unable to load files'), findsNothing);
  });

  group('menu actions', () {
    const node = FileNode(
      name: 'notes.txt',
      size: 12,
      isDir: false,
      deviceName: 'Internal',
      devicePath: '',
      deviceSerial: '',
      dirPath: '.trash/20260901T120000Z_ab12_notes.txt',
    );

    Future<List<FileMenuAction>> pumpWithActions(
      WidgetTester tester, {
      Set<FileMenuAction>? menuActions,
      void Function(FileNode)? onOpenDirectory,
      String? subtitle,
    }) async {
      final dispatched = <FileMenuAction>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileBrowserView(
              filesFuture: Future.value(const [node]),
              currentPath: '',
              onFileMenuAction: (_, action) async => dispatched.add(action),
              onOpenDirectory: onOpenDirectory,
              isGridView: false,
              menuActions: menuActions ?? FileBrowserView.defaultMenuActions,
              subtitleFor: subtitle == null ? null : (_) => subtitle,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return dispatched;
    }

    testWidgets('the trash offers only Restore and Delete permanently', (
      tester,
    ) async {
      final dispatched = await pumpWithActions(
        tester,
        menuActions: const {
          FileMenuAction.restore,
          FileMenuAction.deletePermanently,
        },
        subtitle: 'From /Docs · 3 days left',
      );

      expect(find.text('From /Docs · 3 days left'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<FileMenuAction>));
      await tester.pumpAndSettle();

      expect(find.text('Restore'), findsOneWidget);
      expect(find.text('Delete permanently'), findsOneWidget);
      for (final label in ['Download', 'Move/Rename', 'Delete']) {
        expect(find.text(label), findsNothing, reason: '$label is offered');
      }

      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(dispatched, [FileMenuAction.restore]);
    });

    testWidgets('a row with no open handler does not open', (tester) async {
      await pumpWithActions(tester);

      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.onTap, isNull);
      // Long-press still starts a selection.
      expect(tile.onLongPress, isNotNull);
    });

    testWidgets('the Files page keeps its menu', (tester) async {
      await pumpWithActions(tester, onOpenDirectory: (_) {});

      await tester.tap(find.byType(PopupMenuButton<FileMenuAction>));
      await tester.pumpAndSettle();

      for (final label in ['Download', 'Move/Rename', 'Delete']) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
      expect(find.text('Restore'), findsNothing);
      expect(find.text('Delete permanently'), findsNothing);
    });
  });
}
