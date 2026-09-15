import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

void main() {
  test('compares by value', () {
    const a = PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada');
    const same = PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada');
    const group = PrincipalItem(kind: PrincipalKind.group, id: 1, name: 'ada');

    expect(a, same);
    expect(a.hashCode, same.hashCode);
    expect(a, isNot(group), reason: 'ids repeat across kinds');
  });

  test('the key suffix names the kind as well as the id', () {
    const user = PrincipalItem(kind: PrincipalKind.user, id: 3, name: 'bob');
    const everyone = PrincipalItem(
      kind: PrincipalKind.group,
      id: 1,
      name: 'everyone',
      isBuiltin: true,
    );

    expect(user.keySuffix, 'user_3');
    expect(everyone.keySuffix, 'group_1');
  });
}
