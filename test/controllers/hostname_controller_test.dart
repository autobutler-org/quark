import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/hostname_controller.dart';
import 'package:quark/models/hostname_status.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';

HostnameStatus _named(String hostname, [String advertised = '']) =>
    HostnameStatus(
      available: true,
      hostname: hostname,
      advertisedHostname: advertised,
    );

/// A controller over a fake Quark called [start], saved in the app as
/// [activeHost], whose renames answer with [renamed].
({
  HostnameController controller,
  List<String> moves,
  StreamController<FileEvent> events,
})
_harness({
  HostnameStatus? start,
  String? activeHost = 'https://quark.local',
  HostnameStatus Function(String name)? renamed,
  Uri? page,
}) {
  final moves = <String>[];
  final events = StreamController<FileEvent>.broadcast(sync: true);
  final controller = HostnameController(
    getStatus: () async => start ?? _named('quark'),
    setHostname: (name) async => (renamed ?? _named)(name),
    events: events.stream,
    activeHost: () => activeHost,
    moveHost: (from, to) async => moves.add('$from -> $to'),
    pageUri: () => page ?? Uri.parse('file:///app'),
  );
  addTearDown(events.close);
  return (controller: controller, moves: moves, events: events);
}

FileEvent _changed(String hostname, [String? advertised]) => FileEvent(
  kind: 'hostname_changed',
  path: '',
  data: {'hostname': hostname, 'advertisedHostname': ?advertised},
);

/// #2344: the device name field's state, and where the app's saved address
/// goes when the name it used stops answering.
void main() {
  test('loads what the Quark is called', () async {
    final h = _harness(start: _named('quark', 'quark-2'));
    await h.controller.load();
    expect(h.controller.status?.hostname, 'quark');
    expect(h.controller.status?.networkName, 'quark-2');
    expect(h.controller.isLoading, isFalse);
    expect(h.controller.error, isNull);
    expect(h.controller.renamedTo, isNull);
    expect(h.moves, isEmpty);
  });

  test('a load that fails leaves the field hidden, with no error', () async {
    final controller = HostnameController(
      getStatus: () async => throw const ApiException(404, 'load hostname'),
      events: const Stream.empty(),
    );
    await controller.load();
    expect(controller.status, isNull);
    expect(controller.error, isNull);
    expect(controller.isLoading, isFalse);
  });

  // #3087: a rename made while the socket was down sent no event this
  // controller saw; the reconnect arrives as a resync.
  test('a resync reads the name again', () async {
    var name = 'quark';
    final events = StreamController<FileEvent>.broadcast(sync: true);
    addTearDown(events.close);
    final controller = HostnameController(
      getStatus: () async => _named(name),
      events: events.stream,
      activeHost: () => null,
    );
    await controller.load();

    name = 'kitchen';
    events.add(const FileEvent(kind: 'resync', path: ''));
    await pumpEventQueue();
    expect(controller.status?.hostname, 'kitchen');
  });

  test('a rename moves the saved address to the new .local name', () async {
    final h = _harness();
    await h.controller.load();
    expect(await h.controller.rename('  kitchen '), isTrue);
    expect(h.controller.status?.hostname, 'kitchen');
    expect(h.controller.renamedTo, 'kitchen.local');
    expect(h.controller.reopenAddress, isNull);
    expect(h.controller.isWorking, isFalse);
    expect(h.moves, ['https://quark.local -> https://kitchen.local']);
  });

  test('the move keeps the scheme, port and case-insensitive match', () async {
    final h = _harness(activeHost: 'https://Quark.local:8443');
    await h.controller.load();
    await h.controller.rename('kitchen');
    expect(h.moves, ['https://Quark.local:8443 -> https://kitchen.local:8443']);
  });

  test('the name the device actually took is the one used', () async {
    final h = _harness(renamed: (name) => _named(name, '$name-2'));
    await h.controller.load();
    await h.controller.rename('kitchen');
    expect(h.controller.renamedTo, 'kitchen-2.local');
    expect(h.moves, ['https://quark.local -> https://kitchen-2.local']);
  });

  test('the name the device was advertising counts as the old one', () async {
    final h = _harness(
      start: _named('quark', 'quark-2'),
      activeHost: 'https://quark-2.local',
    );
    await h.controller.load();
    await h.controller.rename('kitchen');
    expect(h.moves, ['https://quark-2.local -> https://kitchen.local']);
  });

  test('an address that never used the old name is left alone', () async {
    for (final host in [
      'https://192.168.1.20',
      'https://attic.local',
      'https://quark.example.com',
      '/',
      null,
    ]) {
      final h = _harness(activeHost: host);
      await h.controller.load();
      expect(await h.controller.rename('kitchen'), isTrue);
      expect(h.moves, isEmpty, reason: '$host');
      expect(h.controller.renamedTo, 'kitchen.local');
    }
  });

  test('a hostname_changed event moves the address the same way', () async {
    final h = _harness();
    await h.controller.load();
    h.events.add(_changed('kitchen', 'kitchen-2'));
    await pumpEventQueue();
    expect(h.controller.status?.hostname, 'kitchen');
    expect(h.controller.status?.available, isTrue);
    expect(h.controller.renamedTo, 'kitchen-2.local');
    expect(h.moves, ['https://quark.local -> https://kitchen-2.local']);
  });

  test('other events, and one before the first load, change nothing', () async {
    final h = _harness();
    h.events.add(_changed('kitchen'));
    h.events.add(const FileEvent(kind: 'upload', path: '/a.txt'));
    await pumpEventQueue();
    expect(h.moves, isEmpty);
    expect(h.controller.renamedTo, isNull);
  });

  test('the event and then the answer move the address once', () async {
    final answer = Completer<HostnameStatus>();
    final moves = <String>[];
    final events = StreamController<FileEvent>.broadcast(sync: true);
    addTearDown(events.close);
    final controller = HostnameController(
      getStatus: () async => _named('quark'),
      setHostname: (name) => answer.future,
      events: events.stream,
      activeHost: () => 'https://quark.local',
      moveHost: (from, to) async => moves.add('$from -> $to'),
      pageUri: () => Uri.parse('file:///app'),
    );
    await controller.load();
    final renaming = controller.rename('kitchen');
    events.add(_changed('kitchen'));
    await pumpEventQueue();
    answer.complete(_named('kitchen'));
    expect(await renaming, isTrue);
    expect(moves, ['https://quark.local -> https://kitchen.local']);
    expect(controller.renamedTo, 'kitchen.local');
  });

  test('a page served from the old name is told where to reopen', () async {
    final h = _harness(
      activeHost: '/',
      page: Uri.parse('https://quark.local/settings/network?x=1'),
    );
    await h.controller.load();
    await h.controller.rename('kitchen');
    expect(h.moves, isEmpty);
    expect(h.controller.reopenAddress, 'https://kitchen.local');
  });

  test('a page on another address is not', () async {
    final h = _harness(
      activeHost: '/',
      page: Uri.parse('https://192.168.1.20:8443/settings'),
    );
    await h.controller.load();
    await h.controller.rename('kitchen');
    expect(h.controller.reopenAddress, isNull);
  });

  test('a move that fails is not a rename that failed', () async {
    final controller = HostnameController(
      getStatus: () async => _named('quark'),
      setHostname: (name) async => _named(name),
      events: const Stream.empty(),
      activeHost: () => 'https://quark.local',
      moveHost: (from, to) async => throw StateError('storage'),
      pageUri: () => Uri.parse('file:///app'),
    );
    await controller.load();
    expect(await controller.rename('kitchen'), isTrue);
    expect(controller.error, isNull);
    expect(controller.renamedTo, 'kitchen.local');
  });

  test('a refused rename says why and moves nothing', () async {
    final moves = <String>[];
    final controller = HostnameController(
      getStatus: () async => _named('quark'),
      setHostname: (name) async =>
          throw const MessageException("this Quark can't be renamed"),
      events: const Stream.empty(),
      activeHost: () => 'https://quark.local',
      moveHost: (from, to) async => moves.add(to),
      pageUri: () => Uri.parse('file:///app'),
    );
    await controller.load();
    expect(await controller.rename('kitchen'), isFalse);
    expect(controller.error, "This Quark can't be renamed.");
    expect(controller.status?.hostname, 'quark');
    expect(controller.renamedTo, isNull);
    expect(controller.isWorking, isFalse);
    expect(moves, isEmpty);

    final failing = HostnameController(
      getStatus: () async => _named('quark'),
      setHostname: (name) async => throw const ApiException(500, 'rename'),
      events: const Stream.empty(),
    );
    await failing.load();
    expect(await failing.rename('kitchen'), isFalse);
    expect(
      failing.error,
      Errors.message(const ApiException(500), 'rename this Quark'),
    );
  });

  test(
    'a rename that outlives the field still moves, but notifies nobody',
    () async {
      final answer = Completer<HostnameStatus>();
      final moves = <String>[];
      final events = StreamController<FileEvent>.broadcast(sync: true);
      addTearDown(events.close);
      final controller = HostnameController(
        getStatus: () async => _named('quark'),
        setHostname: (name) => answer.future,
        events: events.stream,
        activeHost: () => 'https://quark.local',
        moveHost: (from, to) async => moves.add(to),
        pageUri: () => Uri.parse('file:///app'),
      );
      await controller.load();
      var notified = 0;
      controller.addListener(() => notified++);
      final renaming = controller.rename('kitchen');
      final before = notified;
      controller.dispose();
      expect(events.hasListener, isFalse);
      answer.complete(_named('kitchen'));
      expect(await renaming, isTrue);
      expect(notified, before);
      expect(moves, ['https://kitchen.local']);
    },
  );
}
