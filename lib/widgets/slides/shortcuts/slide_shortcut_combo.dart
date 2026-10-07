import 'package:flutter/material.dart';
import 'package:quark/utils/slide_shortcuts.dart';
import 'package:quark_widgets/quark_widgets.dart';

import 'slide_key_cap.dart';

/// One key combination as a row of [SlideKeyCap]s joined by "+" (nothing on
/// a Mac, where the symbols run together).
///
/// ```dart
/// SlideShortcutCombo(combo: ['Mod', 'Z'], platform: TargetPlatform.macOS);
/// ```
class SlideShortcutCombo extends StatelessWidget {
  /// The caps for [combo], spelled for [platform].
  const SlideShortcutCombo({
    required this.combo,
    required this.platform,
    super.key,
  });

  /// The keys held together, as [SlideShortcut.combos] lists them.
  final List<String> combo;

  /// Whose key names to print.
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final plus = !SlideShortcuts.usesCommand(platform);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: tokens.spacingXs,
      runSpacing: tokens.spacingXs,
      children: [
        for (final (i, cap) in SlideShortcuts.capsFor(
          combo,
          platform,
        ).indexed) ...[
          if (plus && i > 0)
            ExcludeSemantics(
              child: Text('+', style: TextStyle(color: tokens.mutedForeground)),
            ),
          SlideKeyCap(label: cap),
        ],
      ],
    );
  }
}
