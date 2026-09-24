import 'package:quark_tsnet/quark_tsnet.dart';
import 'package:test/test.dart';

// These call the real native library, which the build hook compiles for the
// host, so they prove the hook, the symbol names and the string marshaling.
// The tailnet round trip itself is covered by go/bridge/bridge_test.go.
void main() {
  test('status reports Stopped before start', () {
    final s = QuarkTsnet.status();
    expect(s.state, 'Stopped');
    expect(s.port, 0);
    expect(s.loopbackUrl, isNull);
  });

  test('start surfaces the bridge error on bad input', () async {
    await expectLater(
      QuarkTsnet.start(
        stateDir: '/nonexistent',
        controlUrl: 'http://127.0.0.1:1',
        authKey: 'unused',
        hostname: 'test',
        upstream: 'https://100.64.0.1',
      ),
      throwsA(
        isA<TsnetException>().having(
          (e) => e.message,
          'message',
          contains('plain HTTP'),
        ),
      ),
    );
    expect(QuarkTsnet.status().error, contains('plain HTTP'));
  });

  test('fromJson reads the bridge JSON', () {
    final s = TsnetStatus.fromJson({
      'state': 'Running',
      'tailnetIPs': ['100.64.0.7'],
      'port': 4242,
      'error': '',
    });
    expect(s.isRunning, isTrue);
    expect(s.tailnetIPs, ['100.64.0.7']);
    expect(s.loopbackUrl.toString(), 'http://127.0.0.1:4242');
  });
}
