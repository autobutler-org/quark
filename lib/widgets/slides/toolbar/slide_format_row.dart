import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/toolbar/slide_format_group_controls.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_actions.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_group.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The wide slide toolbar's second row: the [SlideToolbarGroup]s that apply
/// to the selection, divided, scrolling sideways when they do not fit. With
/// nothing selected only the clipboard shows, followed by how to get
/// formatting controls.
///
/// Key prefixes: `slide_format_hint` on the empty state; the groups' own.
class SlideFormatRow extends StatelessWidget {
  /// The row for [actions]' selection.
  const SlideFormatRow({required this.actions, super.key});

  /// What the controls do.
  final SlideToolbarActions actions;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final groups = [
      for (final group in SlideToolbarGroup.values)
        if (group.appliesTo(actions)) group,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, group) in groups.indexed) ...[
            if (i > 0)
              SizedBox(
                height: 28,
                child: VerticalDivider(width: 16, color: tokens.border),
              ),
            SlideFormatGroupControls(group: group, actions: actions),
          ],
          if (!actions.hasSelection)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacingMd),
              child: Text(
                'Select something on the slide to format it',
                key: const ValueKey('slide_format_hint'),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: tokens.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }
}
