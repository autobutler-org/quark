import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/export_photos_controller.dart';
import 'package:quark/models/album_export.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/models/job.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/photos/export/export_explanation.dart';
import 'package:quark/widgets/photos/export/export_photos_dialog.dart';
import 'package:quark/widgets/photos/export/export_running_view.dart';
import 'package:quark_widgets/quark_widgets.dart';

const _albums = [
  AlbumItem(id: 99, name: 'Favorites', isSystem: true, isFavorites: true),
  AlbumItem(
    id: 1,
    name: 'Holiday',
    itemCount: 3,
    children: [AlbumItem(id: 2, name: 'Beach', parentId: 1, itemCount: 1)],
  ),
  AlbumItem(id: 3, name: 'Garden', itemCount: 5),
];

const _devices = [
  StorageDevice(
    name: 'Quark',
    devicePath: '/dev/mmc',
    mountPoint: '/',
    fileSystem: 'ext4',
    totalBytes: 1,
    usedBytes: 0,
    availableBytes: 1,
    isInternal: true,
    isEnabled: true,
    role: 'default-storage',
  ),
  StorageDevice(
    name: 'Grandma USB',
    devicePath: '/dev/sda1',
    mountPoint: '/media/usb',
    fileSystem: 'exfat',
    totalBytes: 1,
    usedBytes: 0,
    availableBytes: 1,
    isInternal: false,
    isEnabled: true,
    serial: 'usb1',
  ),
];

FileNode _dir(String name) => FileNode(
  name: name,
  size: 0,
  isDir: true,
  deviceName: '',
  devicePath: '',
  deviceSerial: 'usb1',
  dirPath: name,
);

Map<String, dynamic> _jobEvent(String status, {double progress = 1}) => {
  'id': 9,
  'kind': JobKinds.photoExport,
  'name': 'Export photos to Holiday',
  'status': status,
  'progress': progress,
  'createdAt': '2026-01-01T00:00:00Z',
};

/// What the fakes saw, and the knobs a test turns.
class _Fakes {
  final events = StreamController<FileEvent>.broadcast();
  final listed = <(String, String)>[];
  final started = <Map<String, Object?>>[];
  Object? startError;
  AlbumExportSummary summary = const AlbumExportSummary(
    jobId: 9,
    status: JobStatus.running,
    deviceSerial: 'usb1',
    relPath: 'Holiday',
  );

  ExportPhotosController controller({
    Set<int> initial = const {},
    bool library = false,
  }) => ExportPhotosController(
    albums: _albums,
    initialAlbumIds: initial,
    scope: library ? ExportScope.library : ExportScope.albums,
    listDevices: () async => _devices,
    listFiles: (path, serial) async {
      listed.add((path, serial));
      return path.isEmpty ? [_dir('Family')] : const [];
    },
    startExport:
        ({
          List<int> albumIds = const [],
          bool library = false,
          required String deviceSerial,
          required String folder,
        }) async {
          started.add({
            'albumIds': albumIds,
            'library': library,
            'deviceSerial': deviceSerial,
            'folder': folder,
          });
          final error = startError;
          if (error != null) throw error;
          return const QueuedAlbumExport(
            jobId: 9,
            deviceSerial: 'usb1',
            relPath: 'Family/Holiday',
          );
        },
    exportSummary: (_) async => summary,
    events: () => events.stream,
  );
}

void main() {
  late _Fakes fakes;
  late List<String> openedJobs;

  setUp(() {
    fakes = _Fakes();
    openedJobs = [];
  });
  tearDown(() => fakes.events.close());

  Future<void> pump(
    WidgetTester tester, {
    Set<int> initial = const {},
    bool library = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ExportPhotosDialog(
                  controller: fakes.controller(
                    initial: initial,
                    library: library,
                  ),
                  onOpenJobs: () => openedJobs.add('jobs'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  /// Scrolls [value] into view in the dialog, then taps it.
  Future<void> tapKey(WidgetTester tester, String value) async {
    await tester.ensureVisible(key(value));
    await tester.pumpAndSettle();
    await tester.tap(key(value));
    await tester.pumpAndSettle();
  }

  /// Chooses the USB drive and its Family folder.
  Future<void> chooseUsbFamily(WidgetTester tester) async {
    await tapKey(tester, 'export_drive_usb1');
    await tapKey(tester, 'export_choose_folder');
    await tapKey(tester, 'folder_picker_row__Family');
    await tapKey(tester, 'folder_picker_select');
  }

  testWidgets('says plainly that it copies, per album, and is no backup', (
    tester,
  ) async {
    await pump(tester, initial: {1});

    for (final point in ExportExplanation.points) {
      expect(find.text(point), findsOneWidget);
    }
    expect(find.textContaining('real copies'), findsOneWidget);
    expect(find.textContaining('not links'), findsOneWidget);
    expect(find.textContaining("copied into each album's folder"), findsOne);
    expect(find.textContaining('not a backup of your Quark'), findsOneWidget);
    // Only the user's own albums are offered, sub-albums included.
    expect(key('export_album_1'), findsOneWidget);
    expect(key('export_album_2'), findsOneWidget);
    expect(key('export_album_99'), findsNothing);
  });

  testWidgets('exports the chosen albums into the chosen drive and folder', (
    tester,
  ) async {
    await pump(tester, initial: {1});
    // The default storage drive starts chosen, but no folder yet.
    expect(tester.widget<FilledButton>(key('export_start')).onPressed, isNull);

    await tapKey(tester, 'export_album_3');
    // Beach is inside Holiday, which already brings it along.
    await tapKey(tester, 'export_album_2');
    await chooseUsbFamily(tester);

    expect(fakes.listed.first, ('', 'usb1'));
    expect(
      find.textContaining('inside /Family on Grandma USB'),
      findsOneWidget,
    );

    await tapKey(tester, 'export_start');

    expect(fakes.started.single, {
      'albumIds': [1, 3],
      'library': false,
      'deviceSerial': 'usb1',
      'folder': '/Family',
    });
    expect(
      find.text(
        'Copying your photos to the folder "Family/Holiday" on Grandma USB.',
      ),
      findsOneWidget,
    );
    expect(find.text(ExportRunningView.followInJobs), findsOneWidget);

    await tapKey(tester, 'export_open_jobs');
    expect(openedJobs, ['jobs']);
    expect(find.byType(ExportPhotosDialog), findsNothing);
  });

  testWidgets('a library export sends no albums', (tester) async {
    await pump(tester, library: true);
    expect(key('export_album_1'), findsNothing);

    await chooseUsbFamily(tester);
    await tapKey(tester, 'export_start');

    expect(fakes.started.single['library'], isTrue);
    expect(fakes.started.single['albumIds'], isEmpty);
  });

  testWidgets('a refused export says why and stays on the choice', (
    tester,
  ) async {
    fakes.startError = const ApiException(403);
    await pump(tester, initial: {1});
    await chooseUsbFamily(tester);

    await tapKey(tester, 'export_start');

    expect(find.text(Errors.exportFolderNotWritable), findsOneWidget);
    expect(key('export_start'), findsOneWidget);
  });

  testWidgets('a partial export lists the photos left out, never "finished"', (
    tester,
  ) async {
    await pump(tester, initial: {1});
    await chooseUsbFamily(tester);
    await tapKey(tester, 'export_start');

    fakes.summary = const AlbumExportSummary(
      jobId: 9,
      status: JobStatus.failed,
      deviceSerial: 'usb1',
      relPath: 'Family/Holiday',
      copied: 2,
      failures: [
        AlbumExportFailure(
          name: 'beach.jpg',
          path: 'Holiday/Beach/beach.jpg',
          reason: AlbumExportFailureReason.missing,
        ),
        AlbumExportFailure(
          name: 'cake.jpg',
          path: 'Holiday/cake.jpg',
          reason: AlbumExportFailureReason.notCopied,
        ),
      ],
      moreFailures: 1,
    );
    fakes.events.add(
      FileEvent(kind: 'job_failed', path: '', data: _jobEvent('failed')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(Errors.exportPartial(failed: 3, copied: 2)),
      findsOneWidget,
    );
    expect(find.text('beach.jpg'), findsOneWidget);
    expect(find.text('cake.jpg'), findsOneWidget);
    expect(
      find.text(Errors.exportFailureReason(missing: true)),
      findsOneWidget,
    );
    expect(
      find.text(Errors.exportFailureReason(missing: false)),
      findsOneWidget,
    );
    expect(find.text('And 1 more photo.'), findsOneWidget);
    expect(find.textContaining('finished.'), findsNothing);
  });

  testWidgets('a complete export says where everything went', (tester) async {
    await pump(tester, initial: {1});
    await chooseUsbFamily(tester);
    await tapKey(tester, 'export_start');

    fakes.summary = const AlbumExportSummary(
      jobId: 9,
      status: JobStatus.completed,
      deviceSerial: 'usb1',
      relPath: 'Family/Holiday',
      copied: 4,
    );
    // Another job's event is not this export's.
    fakes.events.add(
      FileEvent(
        kind: 'job_completed',
        path: '',
        data: {..._jobEvent('completed'), 'id': 10},
      ),
    );
    await tester.pumpAndSettle();
    expect(key('export_result_message'), findsNothing);

    fakes.events.add(
      FileEvent(kind: 'job_completed', path: '', data: _jobEvent('completed')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The export is finished. 4 files went to the folder '
        '"Family/Holiday" on Grandma USB.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a canceled export says it stopped', (tester) async {
    await pump(tester, initial: {1});
    await chooseUsbFamily(tester);
    await tapKey(tester, 'export_start');

    fakes.summary = const AlbumExportSummary(
      jobId: 9,
      status: JobStatus.canceled,
      deviceSerial: 'usb1',
      relPath: 'Family/Holiday',
      copied: 1,
    );
    fakes.events.add(
      FileEvent(kind: 'job_canceled', path: '', data: _jobEvent('canceled')),
    );
    await tester.pumpAndSettle();

    expect(find.text(Errors.exportStopped), findsOneWidget);
  });
}
