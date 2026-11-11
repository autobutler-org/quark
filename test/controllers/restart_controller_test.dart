import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/restart_controller.dart';
import 'package:quark/models/restart_status.dart';
import 'package:quark/utils/error_text.dart';

/// [answers] says, per version request, whether the Quark answers; past the
/// end it always does.
RestartController _controllerFor(
  RestartStatus status, {
  Future<void> Function()? restart,
  List<bool> answers = const [],
  void Function()? onVersionRequest,
}) {
  var requests = 0;
  return RestartController(
    getStatus: () async => status,
    restart: restart ?? () async {},
    getInstalledVersion: () async {
      onVersionRequest?.call();
      final answered = requests < answers.length ? answers[requests] : true;
      requests++;
      if (!answered) throw const ApiException(502, 'get version');
      return <String, dynamic>{};
    },
    exitPause: Duration.zero,
    pollInterval: const Duration(milliseconds: 1),
    timeout: const Duration(milliseconds: 20),
  );
}

void main() {
  test('is available when the Quark says so', () async {
    final controller = _controllerFor(const RestartStatus(available: true));
    expect(controller.isAvailable, isFalse);
    await controller.load();
    expect(controller.isAvailable, isTrue);
  });

  test('is not available when nothing starts the Quark again', () async {
    final controller = _controllerFor(
      const RestartStatus(
        available: false,
        reason: RestartStatus.notSupervised,
      ),
    );
    await controller.load();
    expect(controller.isAvailable, isFalse);
  });

  test('a load failure keeps the section hidden', () async {
    final controller = RestartController(
      getStatus: () async => throw const ApiException(500, 'load restart'),
    );
    await controller.load();
    expect(controller.isAvailable, isFalse);
    expect(controller.error, isNull);
  });

  test('waits until the Quark answers again', () async {
    var versionRequests = 0;
    final controller = _controllerFor(
      const RestartStatus(available: true),
      answers: [false, false],
      onVersionRequest: () => versionRequests++,
    );
    final restarting = controller.restart();
    expect(controller.isWorking, isTrue);
    await restarting;
    expect(versionRequests, 3);
    expect(controller.isRestarting, isFalse);
    expect(controller.isBack, isTrue);
    expect(controller.error, isNull);
  });

  test('is restarting between the request and the answer', () async {
    final controller = _controllerFor(
      const RestartStatus(available: true),
      answers: [false],
    );
    final seen = <bool>[];
    controller.addListener(() => seen.add(controller.isRestarting));
    await controller.restart();
    expect(seen, contains(isTrue));
    expect(controller.isRestarting, isFalse);
  });

  test('a Quark that never answers becomes copy from Errors', () async {
    final controller = _controllerFor(
      const RestartStatus(available: true),
      answers: List.filled(100, false),
    );
    await controller.restart();
    expect(controller.isBack, isFalse);
    expect(controller.isRestarting, isFalse);
    expect(controller.error, Errors.restartDidNotFinish);
  });

  test(
    'a refused restart becomes copy from Errors and does not wait',
    () async {
      var versionRequests = 0;
      final controller = _controllerFor(
        const RestartStatus(available: true),
        restart: () async => throw const MessageException(
          'an update or restart is already in progress',
        ),
        onVersionRequest: () => versionRequests++,
      );
      await controller.restart();
      expect(
        controller.error,
        Errors.message(
          const MessageException('an update or restart is already in progress'),
          'restart Quark',
        ),
      );
      expect(controller.isWorking, isFalse);
      expect(controller.isRestarting, isFalse);
      expect(versionRequests, 0);
    },
  );
}
