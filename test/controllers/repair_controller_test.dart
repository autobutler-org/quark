import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/repair_controller.dart';
import 'package:quark/models/repair_status.dart';
import 'package:quark/utils/error_text.dart';

RepairController _controllerFor(
  RepairStatus status, {
  Future<void> Function()? repair,
}) => RepairController(
  getStatus: () async => status,
  repair: repair ?? () async {},
);

void main() {
  test('offers repair when it is available', () async {
    final controller = _controllerFor(const RepairStatus(available: true));
    await controller.load();
    expect(controller.isHidden, isFalse);
    expect(controller.needsInstall, isFalse);
    expect(controller.status?.available, isTrue);
  });

  test('an outdated unit is shown, with the install instruction', () async {
    final controller = _controllerFor(
      const RepairStatus(available: false, reason: RepairStatus.unitOutdated),
    );
    await controller.load();
    expect(controller.isHidden, isFalse);
    expect(controller.needsInstall, isTrue);
  });

  for (final reason in [RepairStatus.unsupportedOs, RepairStatus.notService]) {
    test('hides the section when the reason is $reason', () async {
      final controller = _controllerFor(
        RepairStatus(available: false, reason: reason),
      );
      await controller.load();
      expect(controller.isHidden, isTrue);
    });
  }

  test('a load failure becomes copy from Errors', () async {
    final controller = RepairController(
      getStatus: () async => throw const ApiException(500, 'load repair'),
    );
    await controller.load();
    expect(controller.isHidden, isFalse);
    expect(
      controller.error,
      Errors.message(
        const ApiException(500, 'load repair'),
        'check whether the installation can be repaired',
      ),
    );
  });

  test('a repair that succeeds reports true', () async {
    var calls = 0;
    final controller = _controllerFor(
      const RepairStatus(available: true),
      repair: () async => calls++,
    );
    expect(await controller.repair(), isTrue);
    expect(calls, 1);
    expect(controller.error, isNull);
    expect(controller.isWorking, isFalse);
  });

  test('a repair that fails becomes copy from Errors', () async {
    final controller = _controllerFor(
      const RepairStatus(available: true),
      repair: () async =>
          throw const MessageException('repair is not available'),
    );
    expect(await controller.repair(), isFalse);
    expect(controller.error, 'Repair is not available.');
    expect(controller.isWorking, isFalse);
  });
}
