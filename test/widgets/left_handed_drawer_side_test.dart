import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The rule this file exists to keep (#1812): left-handed mode moves the
/// drawer to the right edge on every page. `QuarkPageScaffold` picks the side
/// for the pages that use it. A page that builds its own `Scaffold` and hands
/// the drawer straight to `drawer:` keeps it on the left whatever the setting
/// says, while its brand button has already moved to the right.
void main() {
  test('no page pins the drawer to the left edge', () {
    final fixedDrawer = RegExp(r'\bdrawer:\s*(const\s+)?AppDrawer\(');
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!fixedDrawer.hasMatch(source)) continue;
      if (!source.contains('QuarkPageScaffold(')) offenders.add(entity.path);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Hand the drawer to QuarkPageScaffold, or pick drawer: or '
          'endDrawer: from QuarkHandedness.isLeftHanded(context).',
    );
  });
}
