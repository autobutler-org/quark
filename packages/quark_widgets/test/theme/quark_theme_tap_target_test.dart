import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump.dart';

/// #2939: Material shrinks its controls on desktop — `shrinkWrap` tap targets
/// and `compact` density bring a stock button down to 32px. Quark's theme
/// holds every platform to 48dp, because a touchscreen laptop, a Chromebook or
/// a tablet asking for the desktop site all report a desktop platform.
void main() {
  for (final platform in TargetPlatform.values) {
    testBothViewports('stock controls are 48dp on ${platform.name}', (
      tester,
      size,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var checked = false;
      await pumpAt(
        tester,
        size: size,
        StatefulBuilder(
          builder: (context, setState) => Center(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Filled')),
                OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
                TextButton(onPressed: () {}, child: const Text('Text')),
                IconButton(
                  tooltip: 'Icon',
                  onPressed: () {},
                  icon: const Icon(Icons.add),
                ),
                Checkbox(
                  semanticLabel: 'Check',
                  value: checked,
                  onChanged: (v) => setState(() => checked = v!),
                ),
                ActionChip(label: const Text('Chip'), onPressed: () {}),
              ],
            ),
          ),
        ),
      );

      final theme = Theme.of(tester.element(find.byType(Wrap)));
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(theme.visualDensity, VisualDensity.standard);
      for (final type in [FilledButton, OutlinedButton, TextButton]) {
        expect(tester.getSize(find.byType(type)).height, 48, reason: '$type');
      }
      await expectTapTargetGuidelines(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
