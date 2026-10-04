import 'package:flutter/material.dart';
import 'package:quark/utils/slide_shortcuts.dart';
import 'package:quark_widgets/quark_widgets.dart';

import 'slide_shortcut_row.dart';

/// A heading and the [SlideShortcutRow]s filed under it.
///
/// Key: `slide_shortcut_section_<name>`, for example
/// `slide_shortcut_section_arrange`.
///
/// ```dart
/// SlideShortcutSectionView(
///   section: SlideShortcutSection.arrange,
///   shortcuts: shortcuts,
///   platform: platform,
/// );
/// ```
class SlideShortcutSectionView extends StatelessWidget {
  /// The [section] heading above [shortcuts], spelled for [platform].
  const SlideShortcutSectionView({
    required this.section,
    required this.shortcuts,
    required this.platform,
    super.key,
  });

  /// The group being drawn.
  final SlideShortcutSection section;

  /// The shortcuts in it, already filtered.
  final List<SlideShortcut> shortcuts;

  /// Whose key names to print.
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Column(
      key: ValueKey('slide_shortcut_section_${section.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Padding(
            padding: EdgeInsets.only(top: tokens.spacingMd),
            child: Text(
              section.label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: tokens.secondaryForeground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        for (final shortcut in shortcuts)
          SlideShortcutRow(shortcut: shortcut, platform: platform),
      ],
    );
  }
}
