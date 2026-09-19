import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

void main() {
  const ada = PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada');
  const bob = PrincipalItem(kind: PrincipalKind.user, id: 2, name: 'bob');

  test('compares by value, members included', () {
    const a = GroupItem(id: 2, name: 'Family', members: [ada]);
    const same = GroupItem(id: 2, name: 'Family', members: [ada]);
    const otherMembers = GroupItem(id: 2, name: 'Family', members: [bob]);

    expect(a, same);
    expect(a.hashCode, same.hashCode);
    expect(a, isNot(otherMembers));
  });

  test('defaults to a group of its own with no members', () {
    const item = GroupItem(id: 2, name: 'Family');

    expect(item.isBuiltin, isFalse);
    expect(item.members, isEmpty);
  });
}
