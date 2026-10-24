import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/file_versions_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/models/file_version.dart';
import 'package:quark/models/path_grant.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/file_browser/archive_text_preview.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu.dart';
import 'package:quark/widgets/file_versions/file_versions_sheet.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The version history sheet (#2992): it loads on open, asks before a
/// restore, previews read-only, and the file menu offers it only for a file
/// on the internal drive.
void main() {
  final old = FileVersion(
    id: 'v1',
    createdAt: DateTime(2026, 10, 9, 8),
    size: 900,
  );
  final backup = FileVersion(
    id: 'v2',
    createdAt: DateTime(2026, 10, 11, 15, 4),
    size: 1200,
    label: 'Before restore',
    authorId: 1,
  );

  Future<List<String>> pumpSheet(
    WidgetTester tester, {
    String name = 'notes.md',
    ListFileVersionsFn? listVersions,
    RestoreFileVersionFn? restoreVersion,
    FileVersionContentFn? loadContent,
  }) async {
    final restored = <String>[];
    var listing = [old];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FileVersionsSheet(
              relPath: 'Docs/$name',
              name: name,
              controller: FileVersionsController(
                path: 'Docs/$name',
                selfUserId: 1,
                listVersions: listVersions ?? (_) async => listing,
                restoreVersion:
                    restoreVersion ??
                    (_, id) async {
                      restored.add(id);
                      listing = [backup, old];
                      return backup;
                    },
                loadContent:
                    loadContent ??
                    (_, _) async => Uint8List.fromList('# old text'.codeUnits),
                loadPrincipals: () async => const SharePrincipals(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return restored;
  }

  testWidgets('loads the history when it opens', (tester) async {
    await pumpSheet(tester);

    expect(find.byKey(const ValueKey('file_version_tile_v1')), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(find.byKey(const ValueKey('refresh_button')), findsOneWidget);
  });

  testWidgets('a failed load reads as a sentence, never the exception', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      listVersions: (_) async => throw const ApiException(500, 'secret'),
    );

    expect(
      find.text(
        Errors.message(const ApiException(500), 'load the version history'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('No earlier versions'), findsNothing);
  });

  testWidgets('restore asks first, and canceling restores nothing', (
    tester,
  ) async {
    final restored = await pumpSheet(tester);

    await tester.tap(find.byKey(const ValueKey('file_version_restore_v1')));
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmDeleteDialog), findsOneWidget);
    expect(find.text('Restore this version?'), findsOneWidget);
    expect(
      find.textContaining('saved first as "Before restore", so you can undo'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('file_version_restore_cancel')));
    await tester.pumpAndSettle();

    expect(restored, isEmpty);
    expect(find.text(FileVersionsSheet.restored), findsNothing);
  });

  testWidgets('a confirmed restore reloads the list and says so', (
    tester,
  ) async {
    final restored = await pumpSheet(tester);

    await tester.tap(find.byKey(const ValueKey('file_version_restore_v1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('file_version_restore_confirm')),
    );
    await tester.pumpAndSettle();

    expect(restored, ['v1']);
    expect(find.byType(ConfirmDeleteDialog), findsNothing);
    expect(find.text(FileVersionsSheet.restored), findsOneWidget);
    expect(find.byKey(const ValueKey('file_version_tile_v2')), findsOneWidget);
    expect(find.textContaining('Before restore · '), findsOneWidget);
  });

  testWidgets('a refused restore reads as a sentence in the sheet', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      restoreVersion: (_, _) async => throw const ApiException(403),
    );

    await tester.tap(find.byKey(const ValueKey('file_version_restore_v1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('file_version_restore_confirm')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        Errors.message(const ApiException(403), 'restore that version'),
      ),
      findsOneWidget,
    );
    expect(find.text(FileVersionsSheet.restored), findsNothing);
  });

  testWidgets('previews a text version read-only', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.byKey(const ValueKey('file_version_preview_v1')));
    await tester.pumpAndSettle();

    expect(find.byType(ArchiveTextPreview), findsOneWidget);
    expect(find.text('# old text'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'nothing to edit');
  });

  testWidgets('says so for a kind with no read-only viewer, fetching nothing', (
    tester,
  ) async {
    var fetched = 0;
    await pumpSheet(
      tester,
      name: 'movie.mp4',
      loadContent: (_, _) async {
        fetched++;
        return Uint8List(0);
      },
    );

    await tester.tap(find.byKey(const ValueKey('file_version_preview_v1')));
    await tester.pumpAndSettle();

    expect(find.text(FileVersionsSheet.previewUnavailable), findsOneWidget);
    expect(fetched, 0);
  });

  testWidgets('will not download a version too large to hold in memory', (
    tester,
  ) async {
    var fetched = 0;
    await pumpSheet(
      tester,
      listVersions: (_) async => [
        FileVersion(
          id: 'v1',
          createdAt: DateTime(2026),
          size: FileVersionsSheet.maxPreviewBytes + 1,
        ),
      ],
      loadContent: (_, _) async {
        fetched++;
        return Uint8List(0);
      },
    );

    await tester.tap(find.byKey(const ValueKey('file_version_preview_v1')));
    await tester.pumpAndSettle();

    expect(find.text(FileVersionsSheet.previewTooLarge), findsOneWidget);
    expect(fetched, 0);
  });

  testWidgets('a preview that fails to load reads as a sentence', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      loadContent: (_, _) async => throw const ApiException(404),
    );

    await tester.tap(find.byKey(const ValueKey('file_version_preview_v1')));
    await tester.pumpAndSettle();

    expect(
      find.text(Errors.message(const ApiException(404), 'load that version')),
      findsOneWidget,
    );
    expect(find.byType(ArchiveTextPreview), findsNothing);
  });

  group('the file menu entry', () {
    FileNode node({bool isDir = false, String serial = ''}) => FileNode(
      name: isDir ? 'Docs' : 'notes.md',
      size: 12,
      isDir: isDir,
      deviceName: 'Drive',
      devicePath: '',
      deviceSerial: serial,
      dirPath: 'Docs',
    );

    Future<List<QuarkMenuEntry>> entries(
      WidgetTester tester,
      FileNode item, {
      bool inArchive = false,
      void Function(FileNode)? onVersionHistory,
    }) async {
      late List<QuarkMenuEntry> result;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            result = FileMenu(
              item: item,
              menuActions: const {},
              extractingPaths: const {},
              inArchive: inArchive,
              isSearchMode: false,
              onDispatchMenuAction: (_, _, _) {},
              onVersionHistory: onVersionHistory,
            ).entries(context);
            return const SizedBox();
          },
        ),
      );
      return result;
    }

    const key = ValueKey('file_version_history');

    testWidgets('is offered on an internal file and hands the file back', (
      tester,
    ) async {
      final opened = <FileNode>[];
      final file = node();
      final offered = await entries(tester, file, onVersionHistory: opened.add);

      expect(offered.single.key, key);
      expect(offered.single.label, 'Version history');
      offered.single.onSelected!();
      expect(opened, [file]);
    });

    testWidgets('is left off a folder, a USB drive, an archive, and a caller '
        'that does not offer it', (tester) async {
      void open(FileNode _) {}

      expect(
        await entries(tester, node(isDir: true), onVersionHistory: open),
        isEmpty,
      );
      expect(
        await entries(tester, node(serial: 'USB1'), onVersionHistory: open),
        isEmpty,
      );
      expect(
        await entries(tester, node(), inArchive: true, onVersionHistory: open),
        isEmpty,
      );
      expect(await entries(tester, node()), isEmpty);
    });
  });
}
