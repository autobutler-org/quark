import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailnet_flutter/services/tunnel_resume.dart';

/// A return to the app keeps a working node and restarts only a broken one
/// (#3882).
void main() {
  group('TunnelLifecycleObserver', () {
    late TunnelLifecycleObserver observer;
    late int returns;

    setUp(() {
      returns = 0;
      observer = TunnelLifecycleObserver()..onReturn = () => returns++;
    });

    void go(List<AppLifecycleState> states) {
      for (final state in states) {
        observer.didChangeAppLifecycleState(state);
      }
    }

    test('an overlay or system prompt is not a return', () {
      // Control Center, Notification Center, Face ID, the share sheet and the
      // photo picker take the app to inactive and straight back.
      go([AppLifecycleState.inactive, AppLifecycleState.resumed]);
      go([AppLifecycleState.inactive, AppLifecycleState.resumed]);
      expect(returns, 0);
    });

    test('coming back from the background is a return, once', () {
      go([
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      expect(returns, 1);
      go([AppLifecycleState.inactive, AppLifecycleState.resumed]);
      expect(returns, 1);
    });

    test('hidden without paused still counts', () {
      go([
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      expect(returns, 1);
    });
  });

  group('resumeTunnelNode', () {
    late int restarts;
    late List<String> probed;

    setUp(() {
      restarts = 0;
      probed = [];
    });

    Future<void> restart() async => restarts++;

    Future<Map<String, dynamic>> Function() reporting(String state, int port) =>
        () async => {'state': state, 'port': port};

    test('keeps a running node that answers through its proxy', () async {
      final restarted = await resumeTunnelNode(
        port: 43210,
        status: reporting('Running', 43210),
        probe: (url) async {
          probed.add(url);
          return true;
        },
        restart: restart,
      );
      expect(restarted, isFalse);
      expect(restarts, 0);
      expect(probed, ['http://127.0.0.1:43210']);
    });

    test('restarts a node that is not running', () async {
      for (final state in ['Stopped', 'Starting', 'NeedsLogin']) {
        final restarted = await resumeTunnelNode(
          port: 43210,
          status: reporting(state, 43210),
          probe: (url) async {
            probed.add(url);
            return true;
          },
          restart: restart,
        );
        expect(restarted, isTrue, reason: state);
      }
      expect(restarts, 3);
      expect(probed, isEmpty);
    });

    test('restarts a node whose proxy moved or stopped listening', () async {
      final restarted = await resumeTunnelNode(
        port: 43210,
        status: reporting('Running', 0),
        probe: (_) async => true,
        restart: restart,
      );
      expect(restarted, isTrue);
      expect(restarts, 1);
    });

    test('restarts a running node the Quark does not answer through', () async {
      final restarted = await resumeTunnelNode(
        port: 43210,
        status: reporting('Running', 43210),
        probe: (_) async => false,
        restart: restart,
      );
      expect(restarted, isTrue);
      expect(restarts, 1);
    });

    test('a probe that throws or hangs means restart', () async {
      expect(
        await resumeTunnelNode(
          port: 43210,
          status: reporting('Running', 43210),
          probe: (_) async => throw StateError('connection refused'),
          restart: restart,
        ),
        isTrue,
      );
      expect(
        await resumeTunnelNode(
          port: 43210,
          status: reporting('Running', 43210),
          probe: (_) => Completer<bool>().future,
          probeTimeout: const Duration(milliseconds: 10),
          restart: restart,
        ),
        isTrue,
      );
      expect(restarts, 2);
    });

    test('with no probe, a running node is kept', () async {
      final restarted = await resumeTunnelNode(
        port: 43210,
        status: reporting('Running', 43210),
        probe: null,
        restart: restart,
      );
      expect(restarted, isFalse);
    });
  });
}
