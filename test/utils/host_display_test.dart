import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/host_display.dart';

/// #2033: the drawer header names the Quark on screen, and the address under
/// the nickname has a drawer's width to say which device that is.
void main() {
  test('drops the scheme, which is the same on every entry', () {
    expect(shortHostAddress('https://quark.home.local'), 'quark.home.local');
    expect(shortHostAddress('http://quark.home.local'), 'quark.home.local');
  });

  test('keeps a port, which is what tells two local Quarks apart', () {
    expect(shortHostAddress('http://localhost:8080'), 'localhost:8080');
    expect(shortHostAddress('https://192.168.1.40:8443'), '192.168.1.40:8443');
  });

  test('drops a trailing slash', () {
    expect(shortHostAddress('https://quark.home.local/'), 'quark.home.local');
  });

  test('leaves something that is not a URL alone', () {
    // The web build stores the origin-relative '/', which has no host to show.
    expect(shortHostAddress('/'), '');
    expect(shortHostAddress('quark.home.local'), 'quark.home.local');
  });

  test('an unset host is an empty label, not "null"', () {
    expect(shortHostAddress(null), '');
    expect(shortHostAddress('   '), '');
  });
}
