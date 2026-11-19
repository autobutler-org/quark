import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/file_browser_controller.dart';
import 'package:quark/models/album_export.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/models/job.dart';
import 'package:quark/services/album_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/quark_widget_items.dart';
import 'package:quark/utils/upload_destination.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What a photo export copies: the chosen albums, or the whole library.
enum ExportScope {
  /// The albums in [ExportPhotosController.selectedAlbumIds], each with its
  /// sub-albums.
  albums,

  /// Every album, and the photos in none.
  library,
}

/// Where an export dialog is: still choosing, asking the Quark to start,
/// copying, or finished with a result.
enum ExportPhase { choosing, starting, running, finished }

/// The state behind the export dialog (#3501): what to export, the drive and
/// folder it goes to, then the job copying it and how it ended.
///
/// Nothing here changes the library or the albums. The Quark makes a new
/// folder of plain copies and a manifest, and runs the copying as a
/// `photo-export` job ([JobKinds.photoExport]) that the dialog follows.
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class ExportPhotosController extends ChangeNotifier {
  /// Creates a controller over the user's [albums] tree. System albums are
  /// left out: only the user's own albums export.
  ExportPhotosController({
    required List<AlbumItem> albums,
    Set<int> initialAlbumIds = const {},
    ExportScope scope = ExportScope.albums,
    Future<List<StorageDevice>> Function() listDevices = listDevicesFresh,
    Future<List<FileNode>> Function(String path, String serial)? listFiles,
    Future<QueuedAlbumExport> Function({
          List<int> albumIds,
          bool library,
          required String deviceSerial,
          required String folder,
        })
        startExport =
        AlbumService.startExport,
    Future<AlbumExportSummary> Function(int jobId) exportSummary =
        AlbumService.exportSummary,
    Stream<FileEvent> Function() events = _appEvents,
  }) : albums = [
         for (final entry in AlbumItem.depthFirst(albums))
           if (!entry.$1.isSystem) entry,
       ],
       _scope = scope,
       _selected = {...initialAlbumIds},
       _listDevices = listDevices,
       _listFiles = listFiles ?? _filesOn,
       _startExport = startExport,
       _exportSummary = exportSummary,
       _events = events;

  /// The user's albums, parents before children, each with its depth.
  final List<(AlbumItem, int)> albums;

  final Future<List<StorageDevice>> Function() _listDevices;
  final Future<List<FileNode>> Function(String path, String serial) _listFiles;
  final Future<QueuedAlbumExport> Function({
    List<int> albumIds,
    bool library,
    required String deviceSerial,
    required String folder,
  })
  _startExport;
  final Future<AlbumExportSummary> Function(int jobId) _exportSummary;
  final Stream<FileEvent> Function() _events;

  StreamSubscription<FileEvent>? _subscription;
  bool _disposed = false;

  ExportScope _scope;
  final Set<int> _selected;
  List<UploadTarget> _drives = const [];
  bool _drivesLoading = false;
  String? _drivesError;
  String? _serial;
  String? _folder;
  ExportPhase _phase = ExportPhase.choosing;
  String? _startError;
  QueuedAlbumExport? _queued;
  double _progress = 0;
  AlbumExportSummary? _summary;
  String? _summaryError;

  /// Whether the albums or the whole library is chosen.
  ExportScope get scope => _scope;

  /// The chosen albums' ids.
  Set<int> get selectedAlbumIds => Set.unmodifiable(_selected);

  /// The drives a person can export to, enabled or not.
  List<UploadTarget> get drives => _drives;

  /// Whether the drives are loading.
  bool get drivesLoading => _drivesLoading;

  /// Copy for a failed drive listing, or null.
  String? get drivesError => _drivesError;

  /// The chosen drive's serial, `''` for the internal drive, or null.
  String? get serial => _serial;

  /// The chosen drive, or null.
  UploadTarget? get drive =>
      _drives.where((d) => d.serial == _serial).firstOrNull;

  /// The chosen folder on [drive], `/` for its top, or null.
  String? get folder => _folder;

  /// Where the dialog is.
  ExportPhase get phase => _phase;

  /// Copy for an export the Quark refused, or null.
  String? get startError => _startError;

  /// The export the Quark queued, once it has.
  QueuedAlbumExport? get queued => _queued;

  /// How far the copying is, from 0 to 1.
  double get progress => _progress;

  /// How the export ended, once it has and the result has been read.
  AlbumExportSummary? get summary => _summary;

  /// Copy for a result that couldn't be read, or null.
  String? get summaryError => _summaryError;

  /// Whether everything an export needs is chosen.
  bool get canStart =>
      _phase == ExportPhase.choosing &&
      (_scope == ExportScope.library || _selected.isNotEmpty) &&
      _serial != null &&
      _folder != null;

  /// Lists [path] on the chosen drive, for the folder picker.
  Future<List<FileNode>> listFolder(String path) =>
      _listFiles(path, _serial ?? '');

  /// Loads the drives, choosing the default storage drive, else the first
  /// one that can be chosen.
  Future<void> loadDrives() async {
    _drivesLoading = true;
    _drivesError = null;
    _notify();
    try {
      final drives = [
        for (final device in await _listDevices()) device.toUploadTarget(),
      ];
      _drives = drives;
      final usable = drives.where((d) => d.unavailableReason == null);
      _serial ??=
          (usable.where((d) => d.isDefault).firstOrNull ?? usable.firstOrNull)
              ?.serial;
    } catch (e) {
      _drivesError = Errors.message(e, 'load your drives');
    }
    _drivesLoading = false;
    _notify();
  }

  /// Chooses what to export.
  void setScope(ExportScope scope) {
    _scope = scope;
    _notify();
  }

  /// Adds or removes album [id] from the export, choosing
  /// [ExportScope.albums].
  void toggleAlbum(int id) {
    if (!_selected.remove(id)) _selected.add(id);
    _scope = ExportScope.albums;
    _notify();
  }

  /// Chooses the drive with [serial]. A folder chosen on another drive is
  /// forgotten.
  void selectDrive(String serial) {
    if (serial == _serial) return;
    _serial = serial;
    _folder = null;
    _notify();
  }

  /// Chooses the folder the export folder is made in.
  void selectFolder(String folder) {
    _folder = folder;
    _startError = null;
    _notify();
  }

  /// Asks the Quark to start the export, then follows its job.
  Future<void> start() async {
    if (!canStart) return;
    _phase = ExportPhase.starting;
    _startError = null;
    _notify();
    try {
      final library = _scope == ExportScope.library;
      _queued = await _startExport(
        albumIds: library ? const [] : _topmostSelected(),
        library: library,
        deviceSerial: _serial!,
        folder: _folder!,
      );
    } catch (e) {
      _startError = Errors.exportStart(e);
      _phase = ExportPhase.choosing;
      _notify();
      return;
    }
    _phase = ExportPhase.running;
    _notify();
    _subscription = _events().listen(_onEvent);
    // The job may have finished before the subscription started.
    await _check();
  }

  /// The chosen albums in list order, less any whose parent is chosen too:
  /// an album exports with its sub-albums, so naming both would copy the
  /// sub-album twice.
  List<int> _topmostSelected() {
    final parents = {for (final (album, _) in albums) album.id: album.parentId};
    bool underChosen(int id) {
      for (var p = parents[id]; p != null; p = parents[p]) {
        if (_selected.contains(p)) return true;
      }
      return false;
    }

    return [
      for (final (album, _) in albums)
        if (_selected.contains(album.id) && !underChosen(album.id)) album.id,
    ];
  }

  void _onEvent(FileEvent event) {
    final queued = _queued;
    if (queued == null || _phase != ExportPhase.running) return;
    if (event.kind == 'resync') {
      unawaited(_check());
      return;
    }
    final data = event.data;
    if (!event.kind.startsWith('job_') || data is! Map<String, dynamic>) {
      return;
    }
    final job = Job.fromJson(data);
    if (job.id != queued.jobId) return;
    _progress = job.progress;
    _notify();
    if (_isOver(job.status)) unawaited(_check(jobOver: true));
  }

  static bool _isOver(JobStatus status) =>
      status == JobStatus.completed ||
      status == JobStatus.failed ||
      status == JobStatus.canceled;

  /// Reads the export's summary and, when its job is over, finishes with it.
  /// A summary that can't be read finishes the dialog only when [jobOver]
  /// says the job has ended; otherwise the next job event tries again.
  Future<void> _check({bool jobOver = false}) async {
    final queued = _queued;
    if (queued == null || _phase != ExportPhase.running) return;
    try {
      final summary = await _exportSummary(queued.jobId);
      if (_disposed || _phase != ExportPhase.running) return;
      if (!_isOver(summary.status)) return;
      _summary = summary;
      _summaryError = null;
    } catch (e) {
      if (_disposed || !jobOver) return;
      _summaryError = Errors.exportSummary(e);
    }
    _phase = ExportPhase.finished;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  static Future<List<FileNode>> _filesOn(String path, String serial) =>
      const FileBrowserController().fetchDeviceFiles(path, serial);

  static Stream<FileEvent> _appEvents() {
    EventsService.instance.start();
    return EventsService.instance.events;
  }
}
