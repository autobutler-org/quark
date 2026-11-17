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
        quarkUnreachableReason(onDevice: true, paused: false, phone: phone),
        QuarkUnreachableReason.notAnswering,
        reason: phone.name,
      );
    }
  });

  // #3881: a page can fail while the connection still reads reachable. A
  // phone still shows its own reason then, never the home Wi-Fi checklist.
  test('a phone always has a reason', () {
    expect(
      quarkUnreachableReason(
        onDevice: true,
        paused: false,
        phone: PhoneRemoteAccess.ready,
      ),
      isNotNull,
    );
  });

  test('the screens name the route, never the home address on a phone', () {
    expect(
      quarkRouteLabel(onDevice: true, mode: ConnectionMode.remote),
      'Using remote access',
    );
    expect(
      quarkRouteLabel(onDevice: false, mode: ConnectionMode.local),
      'Using your home network',
    );
    expect(quarkRouteLabel(onDevice: true, mode: ConnectionMode.offline), '');
    expect(
      quarkRouteLabel(onDevice: false, mode: ConnectionMode.offline),
      isNull,
    );
  });
}
