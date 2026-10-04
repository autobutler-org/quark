import 'package:flutter/material.dart';
import 'package:quark/utils/slide_shortcuts.dart';
import 'package:quark_widgets/quark_widgets.dart';

import 'slide_shortcut_combo.dart';

/// One line of the shortcuts list: what the shortcut does, and under it each
/// key combination that does it, separated by "or".
///
/// The row is one semantics node reading "Redo, Control Shift Z or Control
/// Y", so a screen reader gets the whole shortcut in one stop.
///
/// Key: `slide_shortcut_<id>`.
///
/// ```dart
/// SlideShortcutRow(shortcut: SlideShortcuts.all.first, platform: platform);
/// ```
class SlideShortcutRow extends StatelessWidget {
  /// The row for [shortcut], spelled for [platform].
  const SlideShortcutRow({
    required this.shortcut,
    required this.platform,
    super.key,
  });

  /// What to list.
  final SlideShortcut shortcut;

  /// Whose key names to print.
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final combos = shortcut.combosFor(platform);
    final spoken = combos
        .map((c) => SlideShortcuts.comboSpoken(c, platform))
        .join(' or ');
    return Semantics(
      container: true,
      label: '${shortcut.label}, $spoken',
      child: ExcludeSemantics(
        child: Padding(
          key: ValueKey('slide_shortcut_${shortcut.id}'),
          padding: EdgeInsets.symmetric(vertical: tokens.spacingSm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shortcut.label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: tokens.foreground),
              ),
              SizedBox(height: tokens.spacingXs),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: tokens.spacingSm,
                runSpacing: tokens.spacingXs,
                children: [
                  for (final (i, combo) in combos.indexed) ...[
                    if (i > 0)
                      Text(
                        'or',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.mutedForeground,
                        ),
                      ),
                    SlideShortcutCombo(combo: combo, platform: platform),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
