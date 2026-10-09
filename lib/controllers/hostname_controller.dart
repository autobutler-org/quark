import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/models/hostname_status.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/hostname_service.dart';
import 'package:quark/utils/error_text.dart';

/// The device name field in Settings and first-boot setup (#2344): what the
/// Quark is called, renaming it, and following it to its new address.
///
/// A renamed Quark stops answering to `<old>.local`. When the app's saved
/// address used that name, a rename made here, or a `hostname_changed` event
/// from one made elsewhere, moves the saved address to `<new>.local`. A page
/// the browser loaded from the old name cannot move itself, so
/// [reopenAddress] says where to go instead.
///
/// Service calls arrive as function parameters defaulting to the real ones,
/// so a test passes fakes without a mocking library.
class HostnameController extends ChangeNotifier {
  /// Creates a controller talking to the real [HostnameService],
  /// [EventsService] and [AppSettings] unless overridden.
  HostnameController({
    Future<HostnameStatus> Function() getStatus = HostnameService.getStatus,
    Future<HostnameStatus> Function(String hostname) setHostname =
        HostnameService.setHostname,
    Stream<FileEvent>? events,
    String? Function() activeHost = _defaultActiveHost,
    Future<void> Function(String from, String to) moveHost = _defaultMoveHost,
    Uri Function() pageUri = _defaultPageUri,
  }) : _getStatus = getStatus,
       _setHostname = setHostname,
       _activeHost = activeHost,
       _moveHost = moveHost,
       _pageUri = pageUri {
    _events = (events ?? EventsService.instance.events).listen(_onEvent);
  }

  final Future<HostnameStatus> Function() _getStatus;
  final Future<HostnameStatus> Function(String hostname) _setHostname;
  final String? Function() _activeHost;
  final Future<void> Function(String from, String to) _moveHost;
  final Uri Function() _pageUri;
  late final StreamSubscription<FileEvent> _events;

  HostnameStatus? _status;
  bool _isLoading = false;
  bool _isWorking = false;
  String? _error;
  String? _renamedTo;
  String? _reopenAddress;
  bool _disposed = false;

  static String? _defaultActiveHost() => AppSettings.instance.activeHost;
  static Uri _defaultPageUri() => Uri.base;
  static Future<void> _defaultMoveHost(String from, String to) =>
      AppSettings.instance.moveHost(from, to);

  /// The last status the Quark sent, or null before the first load and when
  /// it could not be read. The field shows only while this says the Quark
  /// can be renamed.
  HostnameStatus? get status => _status;

  /// Whether the status is being fetched.
  bool get isLoading => _isLoading;

  /// Whether a rename is in flight. The field disables its button.
  bool get isWorking => _isWorking;

  /// User-facing copy for the last failed rename, or null. Always from
  /// [Errors].
  String? get error => _error;

  /// The Quark's `.local` name after a rename this controller saw, such as
  /// `kitchen.local`; null before one.
  String? get renamedTo => _renamedTo;

  /// The address to open after a rename, such as `https://kitchen.local`,
  /// when the page itself was loaded from the old `.local` name: the web app,
  /// whose saved address is `/` and so cannot be moved. Null otherwise.
  String? get reopenAddress => _reopenAddress;

  /// Fetches the status. A failure leaves [status] null and sets no [error]:
  /// a Quark too old to have the endpoint just has no field.
  Future<void> load() async {
    _isLoading = true;
    _notify();
    try {
      await _apply(await _getStatus());
    } catch (error) {
      debugPrint('[hostname_controller.dart] load failed: $error');
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Renames the Quark to [name], trimmed. True on success.
  Future<bool> rename(String name) async {
    _isWorking = true;
    _error = null;
    _notify();
    try {
      await _apply(await _setHostname(name.trim()));
      return true;
    } catch (error) {
      _error = Errors.message(error, 'rename this Quark');
      return false;
    } finally {
      _isWorking = false;
      _notify();
    }
  }

  void _onEvent(FileEvent event) {
    final data = event.data;
    if (event.kind != 'hostname_changed' || data is! Map<String, dynamic>) {
      return;
    }
    unawaited(_apply(HostnameStatus.fromJson({...data, 'available': true})));
  }

  /// Takes [next] as the status and, when the Quark's name changed from the
  /// one last seen, follows it. The status is replaced before anything is
  /// awaited: a rename is heard twice, as an event and as the answer, and the
  /// second has to find nothing left to do.
  Future<void> _apply(HostnameStatus next) async {
    final previous = _status;
    _status = next;
    if (previous == null ||
        (previous.hostname == next.hostname &&
            previous.networkName == next.networkName)) {
      _notify();
      return;
    }
    final oldHosts = {
      for (final name in [previous.hostname, previous.advertisedHostname])
        if (name.isNotEmpty) '$name.local',
    };
    final newHost = '${next.networkName}.local';
    _renamedTo = newHost;
    final page = _pageUri();
    _reopenAddress = oldHosts.contains(page.host.toLowerCase())
        ? page.replace(host: newHost).origin
        : null;
    _notify();

    final active = _activeHost();
    final uri = active == null ? null : Uri.tryParse(active);
    if (active == null ||
        uri == null ||
        !oldHosts.contains(uri.host.toLowerCase())) {
      return;
    }
    try {
      await _moveHost(active, uri.replace(host: newHost).toString());
    } catch (error) {
      // The Quark is renamed either way; the address can be fixed by hand.
      debugPrint('[hostname_controller.dart] saved host not moved: $error');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events.cancel());
    super.dispose();
  }
}
