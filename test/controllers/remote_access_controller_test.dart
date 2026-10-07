import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/remote_access_controller.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2857: the remote access controller's state, setup stage, polling, and
/// changes, against fake services.
void main() {
  const off = RemoteAccessStatus(enabled: false);
  const connecting = RemoteAccessStatus(enabled: true);
  const on = RemoteAccessStatus(
    enabled: true,
    connected: true,
    remoteUrl: 'http://100.64.0.7:80',
  );
  const failing = RemoteAccessStatus(enabled: true, error: 'tsnet: rejected');

  test('maps a status to a state', () {
    expect(RemoteAccessController.stateOf(null), RemoteAccessState.off);
    expect(RemoteAccessController.stateOf(off), RemoteAccessState.off);
    expect(
      RemoteAccessController.stateOf(connecting),
      RemoteAccessState.connecting,
    );
    expect(RemoteAccessController.stateOf(on), RemoteAccessState.on);
    expect(RemoteAccessController.stateOf(failing), RemoteAccessState.failing);
  });

  test('load reads the status, and a failure becomes copy', () async {
    var answer = off;
    Object? thrown;
    final controller = RemoteAccessController(
      getStatus: () async {
        if (thrown != null) throw thrown;
        return answer;
      },
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.state, RemoteAccessState.off);
    expect(controller.error, isNull);
    expect(controller.loadFailure, isNull);

    thrown = ApiException(500, 'status');
    await controller.load();
    expect(controller.error, Errors.message(thrown, 'load remote access'));
    expect(controller.loadFailure, thrown);
    expect(controller.isLoading, isFalse);

    thrown = null;
    answer = on;
    await controller.load();
    expect(controller.state, RemoteAccessState.on);
    expect(controller.error, isNull);
  });

  // testWidgets for its fake clock: tester.pump moves the poll's timer.
  testWidgets('enable moves setup from preparing to connecting to done', (
    tester,
  ) async {
    var answer = connecting;
    final controller = RemoteAccessController(
      getStatus: () async => answer,
      enable: () async => connecting,
      pollInterval: const Duration(seconds: 3),
    );
    addTearDown(controller.dispose);

    final enabling = controller.enable();
    expect(controller.setupStage, RemoteAccessSetupStage.preparing);
    expect(await enabling, isNull);
    expect(controller.setupStage, RemoteAccessSetupStage.connecting);

    answer = on;
    await tester.pump(const Duration(seconds: 3));
    expect(controller.setupStage, RemoteAccessSetupStage.done);
  });

  testWidgets('polls only while on and not connected', (tester) async {
    var reads = 0;
    var answer = connecting;
    final controller = RemoteAccessController(
      getStatus: () async {
        reads++;
        return answer;
      },
      pollInterval: const Duration(seconds: 3),
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(reads, 1);

    await tester.pump(const Duration(seconds: 3));
    expect(reads, 2);

    answer = on;
    await tester.pump(const Duration(seconds: 3));
    final settled = reads;
    await tester.pump(const Duration(seconds: 30));
    expect(reads, settled);
  });

  test('a refused change returns copy and leaves the status', () async {
    final controller = RemoteAccessController(
      getStatus: () async => off,
      enable: () async => throw ApiException(403, 'enable'),
      disable: () async => throw ApiException(500, 'disable'),
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(
      await controller.enable(),
      Errors.message(ApiException(403, 'enable'), 'turn on remote access'),
    );
    expect(controller.state, RemoteAccessState.off);
    expect(controller.isWorking, isFalse);
    expect(
      await controller.disable(),
      Errors.message(ApiException(500, 'disable'), 'turn off remote access'),
    );
  });

  test('disable turns it off', () async {
    final controller = RemoteAccessController(
      getStatus: () async => on,
      disable: () async => off,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.disable(), isNull);
    expect(controller.state, RemoteAccessState.off);
  });

  test('a failure sends setup back to the intro', () async {
    final controller = RemoteAccessController(getStatus: () async => failing);
    addTearDown(controller.dispose);
    await controller.load();

    expect(controller.state, RemoteAccessState.failing);
    expect(controller.setupStage, RemoteAccessSetupStage.intro);
  });
}
