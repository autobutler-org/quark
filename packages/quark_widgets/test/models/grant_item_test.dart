import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

void main() {
  const bob = PrincipalItem(kind: PrincipalKind.user, id: 2, name: 'bob');

  test('compares by value, the folder included', () {
    const a = GrantItem(principal: bob, level: AccessLevel.write);
    const same = GrantItem(principal: bob, level: AccessLevel.write);
    const inherited = GrantItem(
      principal: bob,
      level: AccessLevel.write,
      inheritedFrom: 'Family',
    );

    expect(a, same);
    expect(a.hashCode, same.hashCode);
    expect(a, isNot(inherited), reason: 'the same account can have both');
  });

  test('is inherited only when it names a folder', () {
    expect(
      const GrantItem(principal: bob, level: AccessLevel.read).isInherited,
      isFalse,
    );
    expect(
      const GrantItem(
        principal: bob,
        level: AccessLevel.read,
        inheritedFrom: 'Family',
      ).isInherited,
      isTrue,
    );
  });

  test('each level has words for the sheet', () {
    expect(AccessLevel.values.map((level) => level.label), [
      'Can view',
      'Can edit',
      'Owner',
    ]);
  });

  test('each level says what it lets someone do (#2475)', () {
    for (final level in AccessLevel.values) {
      expect(level.description, endsWith('.'), reason: level.name);
    }
    expect(AccessLevel.read.description, 'Can open and download it.');
    expect(AccessLevel.owner.description, contains('change who has access'));
    expect(AccessLevel.owner.description, contains('trust'));
  });
}
