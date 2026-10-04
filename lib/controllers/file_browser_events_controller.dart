import 'dart:async';

import 'package:quark/services/events_service.dart';
import 'package:quark/utils/events_config.dart';
import 'package:quark/utils/file_event_scope.dart';

/// Decides when the Files page refreshes for what the Quark's event socket
/// says (#2763).
///
/// An event counts only when [eventAffectsFolder] says it can change the
/// folder on screen, and counted events are debounced: the refresh runs once
/// [quiet] has passed with no more of them, or [maxWait] after the first, so
/// a 500-file upload into the folder costs one refresh rather than 500, and
/// one into some other folder costs none. A resync or a reconnect means
/// events were lost, so it refreshes at once and takes any pending refresh
/// with it. Nothing refreshes while [isBusy] says the page's own upload is
/// running: that refreshes once when it drains.
class FileBrowserEventsController {
  FileBrowserEventsController({
    required String Function() currentFolder,
    required bool Function() isBusy,
    required void Function() onRefresh,
    Stream<FileEvent>? events,
    Stream<void>? reconnects,
    this.quiet = EventsConfig.refreshQuiet,
    this.maxWait = EventsConfig.refreshMaxWait,
    DateTime Function()? now,
    Timer Function(Duration, void Function())? timer,
  }) : _currentFolder = currentFolder,
       _isBusy = isBusy,
       _onRefresh = onRefresh,
       _now = now ?? DateTime.now,
       _timer = timer ?? Timer.new {
    _eventSub = (events ?? EventsService.instance.events).listen(_onEvent);
    _reconnectSub = (reconnects ?? EventsService.instance.reconnects).listen(
      (_) => _refreshNow(),
    );
  }

  /// How long after the last counted event the refresh waits.
  final Duration quiet;

  /// The longest a steady stream of counted events can hold a refresh back.
  final Duration maxWait;

  final String Function() _currentFolder;
  final bool Function() _isBusy;
  final void Function() _onRefresh;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _timer;

  late final StreamSubscription<FileEvent> _eventSub;
  late final StreamSubscription<void> _reconnectSub;
  Timer? _pending;

  /// When the first event the pending refresh is waiting on arrived.
  DateTime? _firstPending;

  void _onEvent(FileEvent event) {
    if (event.kind == 'resync') {
      _refreshNow();
      return;
    }
    if (!eventAffectsFolder(event, _currentFolder())) return;
    final now = _now();
    final first = _firstPending ??= now;
    final untilMax = first.add(maxWait).difference(now);
    _pending?.cancel();
    _pending = _timer(untilMax < quiet ? untilMax : quiet, _refreshNow);
  }

  void _refreshNow() {
    _pending?.cancel();
    _pending = null;
    _firstPending = null;
    if (!_isBusy()) _onRefresh();
  }

  /// Stops listening and drops any pending refresh.
  void dispose() {
    _pending?.cancel();
    _eventSub.cancel();
    _reconnectSub.cancel();
  }
}
