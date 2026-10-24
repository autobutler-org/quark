import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/file_browser_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// #3193: the Move / Rename dialog could not reliably move a file to another
/// storage device. Each test drives the Files page's move action through the
/// real dialog and reads the `PUT /api/v0/files` body it sends, if any.
void main() {
  Map<String, Object?> device(
    String name, {
    String serial = '',
    bool isEnabled = true,
  }) => {
    'name': name,
    'devicePath': '/dev/$name',
    'mountPoint': '/mnt/$name',
    'isInternal': serial.isEmpty,
    'isEnabled': isEnabled,
    if (serial.isNotEmpty) 'usbInfo': {'serial': serial},
  };

  FileNode node(String path, {String serial = '', bool isDir = false}) =>
      FileNode(
        name: path.split('/').last,
        size: 0,
        isDir: isDir,
        deviceName: '',
        devicePath: '',
        deviceSerial: serial,
        dirPath: path,
      );

  late List<Map<String, Object?>> devices;
  late List<Map<String, dynamic>> moves;

  /// The folders on each drive, by serial. A listing is answered from this
  /// the way the Quark answers it: no `serial` is every drive merged, with a
  /// folder on several drives reported once as the first drive's.
  late Map<String, Set<String>> folders;

  http.Response listing(Uri url) {
    final rootDir = url.queryParameters['rootDir'] ?? '';
    final asked = url.queryParametersAll['serial'] ?? const <String>[];
    final seen = <String>{};
    final rows = [
      for (final MapEntry(key: serial, value: paths) in folders.entries)
        if (asked.isEmpty || asked.contains(serial))
          for (final path in paths)
            if ((path.contains('/')
                        ? path.substring(0, path.lastIndexOf('/'))
                        : '') ==
                    rootDir &&
                seen.add(path))
              {
                'name': path.split('/').last,
                'isDir': true,
                'dirPath': path,
                'deviceSerial': serial,
              },
    ];
    final exists =
        rootDir.isEmpty ||
        folders.entries.any(
          (e) =>
              (asked.isEmpty || asked.contains(e.key)) &&
              e.value.contains(rootDir),
        );
    return exists
        ? http.Response(jsonEncode(rows), 200)
        : http.Response('{"error":"folder not found"}', 404);
  }

  setUp(() {
    devices = [device('Built-in'), device('Stick', serial: 'USB1')];
    moves = [];
    folders = {
      '': {'Docs'},
      'USB1': {'Docs'},
    };
    StorageService.invalidateDeviceCache();
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.url.path.endsWith('/storage/devices/status')) {
        return http.Response(jsonEncode({'devices': devices}), 200);
      }
      if (request.method == 'PUT') {
        moves.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 202);
      }
      if (request.url.path == '/api/v0/files') return listing(request.url);
      return http.Response('[]', 200);
    });
  });

  tearDown(() {
    StorageService.invalidateDeviceCache();
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  /// Opens the move dialog for [moved] and returns the action's outcome once
  /// the dialog closes.
  Future<Future<FileMenuActionOutcome?>> open(
    WidgetTester tester,
    FileNode moved,
  ) async {
    setViewport(tester, const Size(1280, 1600));
    late Future<FileMenuActionOutcome?> outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                outcome = const FileBrowserController().handleFileAction(
                  node: moved,
                  action: FileMenuAction.moveRename,
                  context: context,
                ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Move / Rename'), findsOneWidget);
    return outcome;
  }

  Future<void> pickDevice(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<StorageDevice>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('the same path on another drive is a move', (tester) async {
    final outcome = await open(tester, node('Docs/a.txt'));
    await pickDevice(tester, 'Stick');
    await save(tester);

    expect((await outcome)?.shouldRefresh, isTrue);
    expect(moves, [
      {
        'oldFilePath': '/Docs/a.txt',
        'newFilePath': '/Docs/a.txt',
        'newDeviceSerial': 'USB1',
      },
    ]);
  });

  testWidgets('a folder moves to the same path on another drive', (
    tester,
  ) async {
    final outcome = await open(tester, node('Docs', isDir: true));
    await pickDevice(tester, 'Stick');
    await save(tester);

    expect((await outcome)?.shouldRefresh, isTrue);
    expect(moves.single['newDeviceSerial'], 'USB1');
  });

  testWidgets('a file on a USB drive moves to built-in storage', (
    tester,
  ) async {
    final outcome = await open(tester, node('Docs/a.txt', serial: 'USB1'));
    await pickDevice(tester, 'Built-in (Internal)');
    await save(tester);

    expect((await outcome)?.shouldRefresh, isTrue);
    expect(moves, [
      {
        'oldFilePath': '/Docs/a.txt',
        'newFilePath': '/Docs/a.txt',
        'oldDeviceSerial': 'USB1',
      },
    ]);
  });

  testWidgets('a rename stays on the drive the file is on', (tester) async {
    // With built-in storage listed first the old default happened to mean
    // "same drive"; two USB drives show the dropdown's real starting point.
    devices = [device('Card', serial: 'USB0'), device('Stick', serial: 'USB1')];
    final outcome = await open(tester, node('Docs/a.txt', serial: 'USB1'));
    await tester.enterText(find.byType(TextField).last, 'b.txt');
    await tester.pump();
    await save(tester);

    expect((await outcome)?.shouldRefresh, isTrue);
    expect(moves, [
      {
        'oldFilePath': '/Docs/a.txt',
        'newFilePath': '/Docs/b.txt',
        'oldDeviceSerial': 'USB1',
        'newDeviceSerial': 'USB1',
      },
    ]);
  });

  testWidgets('nothing is sent when neither path nor drive changes', (
    tester,
  ) async {
    final outcome = await open(tester, node('Docs/a.txt', serial: 'USB1'));
    await save(tester);

    expect(await outcome, isNull);
    expect(moves, isEmpty);
  });

  testWidgets('a drive that is not mounted is not offered', (tester) async {
    devices.add(device('Unplugged', serial: 'USB2', isEnabled: false));
    await open(tester, node('Docs/a.txt'));
    await tester.tap(find.byType(DropdownButtonFormField<StorageDevice>));
    await tester.pumpAndSettle();

    expect(find.text('Stick'), findsWidgets);
    expect(find.text('Unplugged'), findsNothing);
  });

  testWidgets("the file's own drive is offered even when not mounted", (
    tester,
  ) async {
    devices.add(device('Unplugged', serial: 'USB2', isEnabled: false));
    await open(tester, node('Docs/a.txt', serial: 'USB2'));

    expect(find.text('Unplugged'), findsOneWidget);
  });

  testWidgets("the folder list is the selected drive's folders", (
    tester,
  ) async {
    folders = {
      '': {'OnBuiltIn'},
      'USB1': {'OnStick'},
    };
    await open(tester, node('a.txt'));

    expect(find.text('OnBuiltIn'), findsOneWidget);
    expect(find.text('OnStick'), findsNothing);

    await pickDevice(tester, 'Stick');

    expect(find.text('OnStick'), findsOneWidget);
    expect(find.text('OnBuiltIn'), findsNothing);

    await pickDevice(tester, 'Built-in (Internal)');

    expect(find.text('OnBuiltIn'), findsOneWidget);
    expect(find.text('OnStick'), findsNothing);
  });

  testWidgets('a folder the other drive lacks falls back to its root', (
    tester,
  ) async {
    folders = {
      '': {'Docs'},
      'USB1': {'Other'},
    };
    final outcome = await open(tester, node('Docs/a.txt'));
    await pickDevice(tester, 'Stick');

    expect(find.text('Other'), findsOneWidget);

    await save(tester);

    expect((await outcome)?.shouldRefresh, isTrue);
    expect(moves, [
      {
        'oldFilePath': '/Docs/a.txt',
        'newFilePath': '/a.txt',
        'newDeviceSerial': 'USB1',
      },
    ]);
  });

  testWidgets('a folder only a USB drive has is not on built-in storage', (
    tester,
  ) async {
    folders = {
      '': <String>{},
      'USB1': {'Docs'},
    };
    final outcome = await open(tester, node('Docs/a.txt', serial: 'USB1'));
    await pickDevice(tester, 'Built-in (Internal)');
    await save(tester);

    expect((await outcome)?.shouldRefresh, isTrue);
    expect(moves, [
      {
        'oldFilePath': '/Docs/a.txt',
        'newFilePath': '/a.txt',
        'oldDeviceSerial': 'USB1',
      },
    ]);
  });
}
