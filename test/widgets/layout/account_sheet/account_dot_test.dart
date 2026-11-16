import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/layout/account_sheet/account_dot.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #4150: when the phone's account button wears its dot.
void main() {
  bool dot({
    int notifications = 0,
    int running = 0,
    ConnectionMode? mode = ConnectionMode.local,
    bool paused = false,
  }) => accountDotShown(
    notifications: notifications,
    running: running,
    mode: mode,
    paused: paused,
  );

  test('no dot when nothing wants a look', () {
    expect(dot(), isFalse);
    expect(dot(mode: ConnectionMode.remote), isFalse);
    expect(dot(mode: null), isFalse, reason: 'the web has no mode');
  });

  test('an unread notification shows the dot', () {
    expect(dot(notifications: 1), isTrue);
  });

  test('a running job or upload shows the dot', () {
    expect(dot(running: 1), isTrue);
  });

  test('remote access paused shows the dot', () {
    expect(dot(paused: true), isTrue);
  });

  test('an offline Quark shows the dot', () {
    expect(dot(mode: ConnectionMode.offline), isTrue);
  });
}
