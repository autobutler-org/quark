import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/file_browser_controller.dart';
import 'package:quark/models/file_device.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// #3989: Move on a multi-selection puts every selected item into one folder
/// or onto a device, keeping each name. The rules match a single Move/Rename.
void main() {
  FileNode file(String path, {String serial = ''}) {
    final name = path.split('/').last;
    return FileNode(
      name: name,
      size: 1,
      isDir: false,
      deviceName: '',
      devicePath: '',
      deviceSerial: serial,
      dirPath: path,
    );
  }

  FileNode folder(
    String path, {
    String serial = '',
    List<FileDevice>? devices,
  }) {
    final name = path.split('/').last;
    return FileNode(
      name: '$name/',
      size: 0,
      isDir: true,
      deviceName: '',
      devicePath: '',
      deviceSerial: serial,
      dirPath: path,
      devices: devices ?? const [],
    );
  }

  late List<Map<String, String?>> moves;

  FileBrowserController controller({
    Future<void> Function({
      required String currentPath,
      required String folderName,
      String? serial,
    })?
    createFolderAt,
  }) {
    return FileBrowserController(
      moveFile: (oldPath, newPath, {oldDeviceSerial, newDeviceSerial}) async {
        moves.add({
          'old': oldPath,
          'new': newPath,
          'oldSerial': oldDeviceSerial,
          'newSerial': newDeviceSerial,
        });
      },
      createFolderAt:
          createFolderAt ??
          ({
            required String currentPath,
            required String folderName,
            String? serial,
          }) async {},
    );
  }

  setUp(() {
    moves = [];
  });

  group('moveNodes', () {
    test('moves each selected item under its own name', () async {
      final outcome = await controller().moveNodes(
        nodes: [file('Docs/a.txt'), folder('Docs/Photos'), file('Notes/b.txt')],
        destinationPath: '/Archive',
        destinationSerial: 'USB1',
        isAdmin: false,
      );

      expect(moves, [
        {
          'old': '/Docs/a.txt',
          'new': '/Archive/a.txt',
          'oldSerial': null,
          'newSerial': 'USB1',
        },
        {
          'old': '/Docs/Photos',
          'new': '/Archive/Photos',
          'oldSerial': null,
          'newSerial': 'USB1',
        },
        {
          'old': '/Notes/b.txt',
          'new': '/Archive/b.txt',
          'oldSerial': null,
          'newSerial': 'USB1',
        },
      ]);
      expect(outcome.moved, 3);
      expect(outcome.failed, 0);
      expect(outcome.leaveSelection, isTrue);
      expect(outcome.message, 'Moved 3 items.');
    });

    test('the top of a device is a destination', () async {
      final outcome = await controller().moveNodes(
        nodes: [file('Docs/a.txt', serial: 'USB1')],
        destinationPath: '',
        destinationSerial: '',
        isAdmin: false,
      );

      expect(moves, [
        {
          'old': '/Docs/a.txt',
          'new': '/a.txt',
          'oldSerial': 'USB1',
          'newSerial': null,
        },
      ]);
      expect(outcome.leaveSelection, isTrue);
      expect(outcome.message, 'Moved 1 item.');
    });

    test('a file keeps its name when the destination already has it', () async {
      await controller().moveNodes(
        nodes: [file('Docs/a.txt'), file('Other/a.txt')],
        destinationPath: '/Dest',
        destinationSerial: '',
        isAdmin: true,
      );

      expect(moves.map((move) => move['new']), ['/Dest/a.txt', '/Dest/a.txt']);
    });

    test('a folder whose name is taken is refused and not renamed', () async {
      final calls = <String>[];
      final refusing = FileBrowserController(
        moveFile: (oldPath, newPath, {oldDeviceSerial, newDeviceSerial}) async {
          calls.add(newPath);
          if (newPath.endsWith('/Docs')) throw const ApiException(409);
        },
      );

      final outcome = await refusing.moveNodes(
        nodes: [file('a.txt'), folder('Docs')],
        destinationPath: '/Dest',
        destinationSerial: '',
        isAdmin: true,
      );

      expect(calls, ['/Dest/a.txt', '/Dest/Docs']);
      expect(outcome.moved, 1);
      expect(outcome.failed, 1);
      expect(outcome.movedPaths, ['a.txt']);
      expect(outcome.leaveSelection, isFalse);
      expect(outcome.message, "Moved 1 item. Couldn't move 1 item.");
    });

    test('a failed move does not undo one that succeeded', () async {
      var calls = 0;
      final flaky = FileBrowserController(
        moveFile: (oldPath, newPath, {oldDeviceSerial, newDeviceSerial}) async {
          calls++;
          if (calls == 2) throw Exception('disk');
        },
      );

      final outcome = await flaky.moveNodes(
        nodes: [file('a.txt'), file('b.txt'), file('c.txt')],
        destinationPath: '/Dest',
        destinationSerial: '',
        isAdmin: true,
      );

      expect(calls, 3);
      expect(outcome.moved, 2);
      expect(outcome.failed, 1);
      expect(outcome.movedPaths, ['a.txt', 'c.txt']);
      expect(outcome.leaveSelection, isFalse);
      expect(outcome.message, "Moved 2 items. Couldn't move 1 item.");
    });

    test('a folder is not moved into itself or a subfolder', () async {
      final outcome = await controller().moveNodes(
        nodes: [folder('Docs'), file('Docs/a.txt'), folder('Other')],
        destinationPath: '/Docs/nested',
        destinationSerial: '',
        isAdmin: true,
      );

      expect(moves.map((move) => move['old']), ['/Docs/a.txt', '/Other']);
      expect(outcome.intoSelf, ['Docs']);
      expect(outcome.leaveSelection, isFalse);
      expect(
        outcome.message,
        "Moved 2 items. Docs can't be moved into itself or one of its subfolders.",
      );
    });

    test('the same path on another device is a move', () async {
      final outcome = await controller().moveNodes(
        nodes: [folder('Docs'), file('Docs/a.txt')],
        destinationPath: '/Docs',
        destinationSerial: 'USB1',
        isAdmin: false,
      );

      expect(moves, [
        {
          'old': '/Docs',
          'new': '/Docs/Docs',
          'oldSerial': null,
          'newSerial': 'USB1',
        },
        {
          'old': '/Docs/a.txt',
          'new': '/Docs/a.txt',
          'oldSerial': null,
          'newSerial': 'USB1',
        },
      ]);
      expect(outcome.intoSelf, isEmpty);
      expect(outcome.leaveSelection, isTrue);
    });

    test('an item already in the destination is not sent again', () async {
      final outcome = await controller().moveNodes(
        nodes: [file('Docs/a.txt')],
        destinationPath: '/Docs',
        destinationSerial: '',
        isAdmin: true,
      );

      expect(moves, isEmpty);
      expect(outcome.moved, 0);
      expect(outcome.leaveSelection, isTrue);
      expect(outcome.message, 'Nothing was moved.');
    });

    test('a merged folder moves from its own serial', () async {
      await controller().moveNodes(
        nodes: [
          folder(
            'Docs',
            serial: 'USB1',
            devices: const [
              FileDevice(serial: 'USB1', name: 'Stick'),
              FileDevice(serial: '', name: 'Built-in'),
            ],
          ),
        ],
        destinationPath: '/Archive',
        destinationSerial: '',
        isAdmin: true,
      );

      expect(moves, [
        {
          'old': '/Docs',
          'new': '/Archive/Docs',
          'oldSerial': 'USB1',
          'newSerial': null,
        },
      ]);
    });

    test('items the menu will not move stay put and are named', () async {
      final outcome = await controller().moveNodes(
        nodes: [
          folder('users'),
          folder('users/alice'),
          folder('groups'),
          folder('groups/Family'),
          file('users/alice/notes.txt'),
          folder('users', serial: 'USB1'),
        ],
        destinationPath: '/Archive',
        destinationSerial: '',
        isAdmin: false,
        inArchive: false,
      );

      expect(moves.map((move) => move['old']), [
        '/users/alice/notes.txt',
        '/users',
      ]);
      expect(moves.last['oldSerial'], 'USB1');
      expect(outcome.left, ['users', 'alice', 'groups', 'Family']);
      expect(outcome.leaveSelection, isFalse);
      expect(
        outcome.message,
        'Moved 2 items. Left users, alice, groups, and Family where they are.',
      );
    });

    test('an admin may move a home, a group folder, and users', () async {
      final outcome = await controller().moveNodes(
        nodes: [
          folder('users'),
          folder('users/alice'),
          folder('groups/Family'),
        ],
        destinationPath: '/Archive',
        destinationSerial: '',
        isAdmin: true,
      );

      expect(outcome.left, isEmpty);
      expect(outcome.moved, 3);
      expect(outcome.leaveSelection, isTrue);
    });

    test('an archive entry stays put', () async {
      final outcome = await controller().moveNodes(
        nodes: [file('photos.zip/beach.jpg'), folder('users')],
        destinationPath: '/Archive',
        destinationSerial: '',
        isAdmin: true,
        inArchive: true,
      );

      expect(moves, isEmpty);
      expect(outcome.left, ['beach.jpg', 'users']);
      expect(outcome.leaveSelection, isFalse);
      expect(outcome.message, 'Left beach.jpg and users where they are.');
    });

    test('every failure stays in selection', () async {
      final refusing = FileBrowserController(
        moveFile: (oldPath, newPath, {oldDeviceSerial, newDeviceSerial}) async {
          throw const ApiException(403);
        },
      );

      final outcome = await refusing.moveNodes(
        nodes: [file('a.txt'), file('b.txt')],
        destinationPath: '/Dest',
        destinationSerial: '',
        isAdmin: true,
      );

      expect(outcome.moved, 0);
      expect(outcome.failed, 2);
      expect(outcome.leaveSelection, isFalse);
      expect(outcome.message, "Couldn't move 2 items.");
    });
  });

  group('move dialog', () {
    late Map<String, Set<String>> folders;
    late List<Map<String, Object?>> created;

    Map<String, Object?> device(String name, {String serial = ''}) => {
      'name': name,
      'devicePath': '/dev/$name',
      'mountPoint': '/mnt/$name',
      'isInternal': serial.isEmpty,
      'isEnabled': true,
      if (serial.isNotEmpty) 'usbInfo': {'serial': serial},
    };

    setUp(() {
      folders = {
        '': {'Docs'},
        'USB1': {'Docs'},
      };
      created = [];
      StorageService.invalidateDeviceCache();
      sharedHttpClientFactory = () => MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path.contains('/files/folder')) {
          created.add({
            'path': request.url.path,
            'serial': request.url.queryParameters['serial'],
          });
          return http.Response('{}', 200);
        }
        if (request.url.path == '/api/v0/files' && request.method == 'GET') {
          final rootDir = request.url.queryParameters['rootDir'] ?? '';
          final rows = [
            for (final paths in folders.values)
              for (final path in paths)
                if ((path.contains('/')
                        ? path.substring(0, path.lastIndexOf('/'))
                        : '') ==
                    rootDir)
                  {
                    'name': path.split('/').last,
                    'isDir': true,
                    'dirPath': path,
                  },
          ];
          return http.Response(jsonEncode(rows), 200);
        }
        return http.Response('[]', 200);
      });
    });

    tearDown(() {
      StorageService.invalidateDeviceCache();
      resetSharedHttpClient();
      sharedHttpClientFactory = buildLocalTrustHttpClient;
    });

    Future<Future<MoveSelectionOutcome?>> open(
      WidgetTester tester,
      FileBrowserController browser, {
      List<FileNode>? nodes,
      List<StorageDevice> devices = const [],
    }) async {
      setViewport(tester, const Size(1280, 1600));
      late Future<MoveSelectionOutcome?> outcome;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => outcome = browser.moveSelection(
                context: context,
                nodes: nodes ?? [file('Docs/a.txt'), file('Docs/b.txt')],
                devices: devices,
                isAdmin: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return outcome;
    }

    testWidgets('has no name field', (tester) async {
      await open(tester, controller());

      expect(find.text('Move / Rename'), findsNothing);
      expect(find.text('New file name'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Move'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'New folder'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('cancel moves nothing and leaves the outcome empty', (
      tester,
    ) async {
      final outcome = await open(tester, controller());
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(await outcome, isNull);
      expect(moves, isEmpty);
    });

    testWidgets('confirm moves the selection into the folder on screen', (
      tester,
    ) async {
      folders[''] = {'Docs', 'Docs/Photos'};
      final outcome = await open(tester, controller());
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Move'));
      await tester.pumpAndSettle();

      expect((await outcome)?.leaveSelection, isTrue);
      expect(moves.map((move) => move['new']), [
        '/Docs/Photos/a.txt',
        '/Docs/Photos/b.txt',
      ]);
    });

    testWidgets('the top of the device is the home of the picker', (
      tester,
    ) async {
      final outcome = await open(tester, controller());
      await tester.tap(find.byKey(const ValueKey('breadcrumb_home')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Move'));
      await tester.pumpAndSettle();

      expect(moves.map((move) => move['new']), ['/a.txt', '/b.txt']);
      expect((await outcome)?.message, 'Moved 2 items.');
    });

    testWidgets('a chosen device is the destination drive', (tester) async {
      final outcome = await open(
        tester,
        controller(),
        devices: [
          StorageDevice.fromJson(device('Built-in')),
          StorageDevice.fromJson(device('Stick', serial: 'USB1')),
        ],
      );
      await tester.tap(find.byType(DropdownButtonFormField<StorageDevice>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stick').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Move'));
      await tester.pumpAndSettle();

      expect(moves.map((move) => move['newSerial']), ['USB1', 'USB1']);
      expect((await outcome)?.leaveSelection, isTrue);
    });

    testWidgets('new folder creates it and moves into it in one confirm', (
      tester,
    ) async {
      String? createdAt;
      String? createdName;
      final outcome = await open(
        tester,
        controller(
          createFolderAt:
              ({required currentPath, required folderName, serial}) async {
                createdAt = currentPath;
                createdName = folderName;
              },
        ),
      );
      await tester.tap(find.widgetWithText(TextButton, 'New folder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Trip');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(createdAt, '/Docs');
      expect(createdName, 'Trip');
      expect(find.widgetWithText(TextButton, 'Move'), findsNothing);
      expect(moves.map((move) => move['new']), [
        '/Docs/Trip/a.txt',
        '/Docs/Trip/b.txt',
      ]);
      expect((await outcome)?.leaveSelection, isTrue);
    });

    testWidgets('a taken folder name moves nothing', (tester) async {
      final outcome = await open(
        tester,
        controller(
          createFolderAt:
              ({required currentPath, required folderName, serial}) async {
                throw const ApiException(409);
              },
        ),
      );
      await tester.tap(find.widgetWithText(TextButton, 'New folder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Docs');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.text(Errors.fileNameTaken), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Move'), findsOneWidget);
      expect(moves, isEmpty);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(await outcome, isNull);
    });
  });
}
