import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/autofill_settings.dart';
import 'package:quark/services/autofill_settings_io.dart' as io;
import 'package:quark/services/autofill_settings_stub.dart' as stub;

/// #3600: the `org.autobutler/autofill` channel as the Dart side speaks it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AutofillSettings.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  void answer(Object? Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return handler(call);
      });

  setUp(() {
    calls = [];
    io.isAndroid = () => true;
  });

  tearDown(() {
    io.isAndroid = () => false;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('reads whether Quark is the service', () async {
    answer((_) => 'enabled');
    expect(await io.status(), AutofillStatus.enabled);
    answer((_) => 'disabled');
    expect(await io.status(), AutofillStatus.disabled);
    expect(calls.map((c) => c.method), ['status', 'status']);
  });

  test('an unknown answer or a failure reads as unsupported', () async {
    answer((_) => 'maybe');
    expect(await io.status(), AutofillStatus.unsupported);
    answer((_) => throw PlatformException(code: 'failed'));
    expect(await io.status(), AutofillStatus.unsupported);
  });

  test('off Android nothing is asked', () async {
    io.isAndroid = () => false;
    answer((_) => 'enabled');
    expect(await io.status(), AutofillStatus.unsupported);
    await expectLater(io.openSettings(), throwsUnsupportedError);
    expect(calls, isEmpty);
  });

  test('opens the system setting', () async {
    answer((_) => null);
    await io.openSettings();
    expect(calls.single.method, 'openSettings');
  });

  test('a device with no setting screen throws', () async {
    answer((_) => throw PlatformException(code: 'unavailable'));
    await expectLater(io.openSettings(), throwsA(isA<PlatformException>()));
  });

  test('web is unsupported', () async {
    expect(await stub.status(), AutofillStatus.unsupported);
    await expectLater(stub.openSettings(), throwsUnsupportedError);
  });
}
