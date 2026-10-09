import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/hostname_rules.dart';

/// #2344: the device name field refuses what the Quark would refuse, with the
/// rule spelled out, before anything is sent.
void main() {
  test('accepts one lowercase label', () {
    for (final name in [
      'quark',
      'kitchen',
      'kitchen-2',
      'a',
      '2nd-floor',
      'a' * 63,
      '  kitchen  ',
    ]) {
      expect(validateHostname(name), isNull, reason: name);
    }
  });

  test('refuses what the Quark refuses, and says the rule', () {
    for (final name in [
      'Kitchen',
      '-kitchen',
      'kitchen-',
      'kitchen.local',
      'kitchen; reboot',
      r'$(reboot)',
      'kitchen\nreboot',
      'my kitchen',
      '42',
      'localhost',
      'a' * 64,
    ]) {
      expect(validateHostname(name), Errors.invalidHostname, reason: name);
    }
  });

  test('an empty name is asked for, not called invalid', () {
    expect(validateHostname(null), 'Name is required');
    expect(validateHostname(''), 'Name is required');
    expect(validateHostname('   '), 'Name is required');
  });
}
