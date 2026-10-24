import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/upload_destination.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage.dart';

/// #3191: which device an upload or a new folder goes to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(mockSecureStorage);

  StorageDevice device(
    String name, {
    String serial = '',
    bool isEnabled = true,
    String role = 'unassigned',
  }) => StorageDevice(
    name: name,
    devicePath: '/dev/$name',
    mountPoint: '/mnt/$name',
    fileSystem: 'ext4',
    totalBytes: 0,
    usedBytes: 0,
    availableBytes: 0,
    isInternal: serial.isEmpty,
    isEnabled: isEnabled,
    serial: serial,
    role: role,
  );

  final builtIn = device('Built-in');
  final stick = device('Stick', serial: 'USB1');

  /// A picker that records what it was offered and where it started, and
  /// answers [choose].
  late List<List<UploadTarget>> offered;
  late List<String> startedOn;
  Future<UploadTarget?> Function(List<UploadTarget>, UploadTarget) picker(
    UploadTarget? Function(List<UploadTarget>) choose,
  ) => (targets, initial) async {
    offered.add(targets);
    startedOn.add(initial.name);
    return choose(targets);
  };

  setUp(() async {
    offered = [];
    startedOn = [];
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
  });

  test('several enabled devices ask, and the answer is the serial', () async {
    final serial = await resolveUploadSerial(
      pick: picker((targets) => targets.last),
      listDevices: () async => [builtIn, stick],
    );

    expect(serial, 'USB1');
    expect(offered.single.map((t) => t.name), ['Built-in', 'Stick']);
  });

  test('built-in storage is the empty serial, not a dismissal', () async {
    final serial = await resolveUploadSerial(
      pick: picker((targets) => targets.first),
      listDevices: () async => [builtIn, stick],
    );

    expect(serial, '');
  });

  test('dismissing the picker is null', () async {
    final serial = await resolveUploadSerial(
      pick: picker((_) => null),
      listDevices: () async => [builtIn, stick],
    );

    expect(serial, isNull);
  });

  test('one device is the destination without asking', () async {
    final serial = await resolveUploadSerial(
      pick: picker((targets) => targets.first),
      listDevices: () async => [stick],
    );

    expect(serial, 'USB1');
    expect(offered, isEmpty);
  });

  group('a drive that is connected but not enabled (#3191)', () {
    final off = device('Off', serial: 'USB0', isEnabled: false);

    test('is offered as unavailable beside the one enabled device, which '
        'the picker starts on', () async {
      final serial = await resolveUploadSerial(
        pick: picker((targets) => targets.last),
        listDevices: () async => [off, stick],
      );

      expect(serial, 'USB1');
      expect(offered.single.map((t) => (t.name, t.unavailableReason != null)), [
        ('Off', true),
        ('Stick', false),
      ]);
      expect(startedOn, ['Stick']);
    });

    test('is never where the picker starts, even when it was chosen last '
        'time', () async {
      await AppSettings.instance.setLastUploadSerial('USB0');

      await resolveUploadSerial(
        pick: picker((_) => null),
        listDevices: () async => [off, builtIn, stick],
      );

      expect(startedOn, ['Built-in']);
    });

    test('is not a destination because the view shows it', () async {
      final serial = await resolveUploadSerial(
        pick: picker((targets) => targets.last),
        viewedSerial: 'USB0',
        listDevices: () async => [off, stick],
      );

      expect(serial, 'USB1');
      expect(offered, hasLength(1));
    });

    test(
      'alone is not a destination: built-in storage, without asking',
      () async {
        final serial = await resolveUploadSerial(
          pick: picker((targets) => targets.first),
          listDevices: () async => [off],
        );

        expect(serial, '');
        expect(offered, isEmpty);
      },
    );
  });

  test('the one device the view shows is the destination', () async {
    for (final viewed in [builtIn, stick]) {
      final serial = await resolveUploadSerial(
        pick: picker((_) => null),
        viewedSerial: viewed.serial,
        listDevices: () async => [builtIn, stick],
      );

      expect(serial, viewed.serial);
    }
    expect(offered, isEmpty);
  });

  test('a viewed device that is no longer enabled asks instead', () async {
    final serial = await resolveUploadSerial(
      pick: picker((targets) => targets.first),
      viewedSerial: 'USB9',
      listDevices: () async => [builtIn, stick],
    );

    expect(serial, '');
    expect(offered, hasLength(1));
  });

  test('a failed device listing is thrown, not built-in storage', () async {
    await expectLater(
      resolveUploadSerial(
        pick: picker((targets) => targets.first),
        listDevices: () async => throw Exception('offline'),
      ),
      throwsException,
    );
    expect(offered, isEmpty);
  });

  test('the device list is read when asked, every time', () async {
    var devices = [builtIn];
    Future<List<StorageDevice>> list() async => devices;
    final pick = picker((targets) => targets.last);

    expect(await resolveUploadSerial(pick: pick, listDevices: list), '');
    devices = [builtIn, stick];
    expect(await resolveUploadSerial(pick: pick, listDevices: list), 'USB1');
  });

  group('the last destination (#3192)', () {
    test('the picker starts on the first device until one is chosen', () async {
      await resolveUploadSerial(
        pick: picker((_) => null),
        listDevices: () async => [builtIn, stick],
      );

      expect(startedOn, ['Built-in']);
    });

    test('a chosen device is kept and starts the picker next time', () async {
      Future<String?> ask(UploadTarget? Function(List<UploadTarget>) choose) =>
          resolveUploadSerial(
            pick: picker(choose),
            listDevices: () async => [builtIn, stick],
          );

      await ask((targets) => targets.last);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('lastUploadSerial'), 'USB1');

      // Dismissing keeps what was chosen before.
      await ask((_) => null);
      await ask((targets) => targets.first);
      await ask((_) => null);

      expect(startedOn, ['Built-in', 'Stick', 'Stick', 'Built-in']);
    });

    test(
      'a kept device that is no longer offered starts on the first',
      () async {
        await AppSettings.instance.setLastUploadSerial('USB9');

        await resolveUploadSerial(
          pick: picker((_) => null),
          listDevices: () async => [builtIn, stick],
        );

        expect(startedOn, ['Built-in']);
      },
    );
  });

  group('the default storage device (#3194)', () {
    final defaultStick = device(
      'Stick',
      serial: 'USB1',
      role: 'default-storage',
    );
    final other = device('Other', serial: 'USB2');

    test('starts the picker, over the device chosen last time', () async {
      await AppSettings.instance.setLastUploadSerial('USB2');

      await resolveUploadSerial(
        pick: picker((_) => null),
        listDevices: () async => [builtIn, defaultStick, other],
      );

      expect(startedOn, ['Stick']);
      expect(offered.single.map((t) => t.isDefault), [false, true, false]);
    });

    test('is still asked about, never chosen without the picker', () async {
      final serial = await resolveUploadSerial(
        pick: picker((targets) => targets.first),
        listDevices: () async => [builtIn, defaultStick],
      );

      expect(serial, '');
      expect(offered, hasLength(1));
    });

    test('built-in storage holding the role starts the picker', () async {
      await AppSettings.instance.setLastUploadSerial('USB1');

      await resolveUploadSerial(
        pick: picker((_) => null),
        listDevices: () async => [
          device('Built-in', role: 'default-storage'),
          stick,
        ],
      );

      expect(startedOn, ['Built-in']);
    });

    test('not enabled, the picker starts on the device chosen last '
        'time', () async {
      await AppSettings.instance.setLastUploadSerial('USB2');

      await resolveUploadSerial(
        pick: picker((_) => null),
        listDevices: () async => [
          builtIn,
          device(
            'Stick',
            serial: 'USB1',
            role: 'default-storage',
            isEnabled: false,
          ),
          other,
        ],
      );

      expect(startedOn, ['Other']);
    });

    test('not connected, the picker starts on the device chosen last time, '
        'then on the first', () async {
      Future<void> ask() => resolveUploadSerial(
        pick: picker((_) => null),
        listDevices: () async => [builtIn, other],
      );

      await ask();
      await AppSettings.instance.setLastUploadSerial('USB2');
      await ask();

      expect(startedOn, ['Built-in', 'Other']);
    });

    test('does not move an upload out of the one device in view', () async {
      final serial = await resolveUploadSerial(
        pick: picker((targets) => targets.first),
        viewedSerial: 'USB2',
        listDevices: () async => [builtIn, defaultStick, other],
      );

      expect(serial, 'USB2');
      expect(offered, isEmpty);
    });

    test('does not replace the last choice when the picker is '
        'dismissed', () async {
      await AppSettings.instance.setLastUploadSerial('USB2');

      await resolveUploadSerial(
        pick: picker((_) => null),
        listDevices: () async => [builtIn, defaultStick, other],
      );

      expect(AppSettings.instance.lastUploadSerial, 'USB2');
    });
  });
}
