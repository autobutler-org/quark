import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/widgets/layout/app_bar_trailing_host.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #3778: a phone replaces the unreachable checklist with the reason it
/// already knows. A browser, which cannot use remote access, keeps the
/// checklist.
void main() {
  test('a browser keeps the checklist', () {
    expect(
      quarkUnreachableReason(
        onDevice: false,
        mode: ConnectionMode.offline,
        paused: false,
        phone: PhoneRemoteAccess.notSetUp,
      ),
      isNull,
    );
  });

  test('a phone that has not set up says to finish at home', () {
    expect(
      quarkUnreachableReason(
        onDevice: true,
        mode: ConnectionMode.offline,
        paused: false,
        phone: PhoneRemoteAccess.notSetUp,
      ),
      QuarkUnreachableReason.notSetUp,
    );
  });

  test('a paused phone says remote access is paused', () {
    expect(
      quarkUnreachableReason(
        onDevice: true,
        mode: ConnectionMode.offline,
        paused: true,
        phone: PhoneRemoteAccess.notSetUp,
      ),
      QuarkUnreachableReason.paused,
    );
  });

  test('a phone that is set up says the Quark is not answering', () {
    for (final phone in [
      PhoneRemoteAccess.settingUp,
      PhoneRemoteAccess.ready,
      PhoneRemoteAccess.notWorking,
    ]) {
      expect(
        quarkUnreachableReason(
          onDevice: true,
          mode: ConnectionMode.offline,
          paused: false,
          phone: phone,
        ),
        QuarkUnreachableReason.notAnswering,
        reason: phone.name,
      );
    }
  });

  test('a reachable Quark has no unreachable reason', () {
    for (final mode in [null, ConnectionMode.local, ConnectionMode.remote]) {
      expect(
        quarkUnreachableReason(
          onDevice: true,
          mode: mode,
          paused: true,
          phone: PhoneRemoteAccess.notSetUp,
        ),
        isNull,
        reason: mode?.name ?? 'unknown',
      );
    }
  });
}
