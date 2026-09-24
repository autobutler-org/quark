import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/tsnet_debug_controller.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/error_text.dart';

void main() {
  test('pair fills the fields from the Quark', () async {
    final c = TsnetDebugController(
      pairDevice: () async => const DevicePairing(
        authKey: 'hskey-auth-x',
        controlUrl: 'https://control.example',
        quarkAddress: 'http://100.64.0.1:80',
      ),
    );
    addTearDown(c.dispose);
    await c.pair();
    expect(c.authKey.text, 'hskey-auth-x');
    expect(c.controlUrl.text, 'https://control.example');
    expect(c.upstream.text, 'http://100.64.0.1:80');
    expect(c.error, isNull);
  });

  test('a Quark without the pairing route says to enter a key', () async {
    final c = TsnetDebugController(
      pairDevice: () async => throw const ApiException(404),
    );
    addTearDown(c.dispose);
    await c.pair();
    expect(c.error, Errors.pairDevice(const ApiException(404)));
    expect(c.error, contains('enter a key by hand'));
    expect(c.busy, isFalse);
  });
}
