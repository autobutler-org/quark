import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/find/slide_find_controller.dart';
import 'package:quark/widgets/slides/find/slide_find_field.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The find bar's replace row: the replacement, then "Replace" — the match
/// the bar is on, moving to the next — and "Replace all". Each is one undo
/// step.
///
/// Side by side on a wide bar; on a [compact] one the buttons go under the
/// field, so neither squeezes the other.
///
/// Key prefixes: `slide_find_replacement` on the field, `slide_find_replace`
/// and `slide_find_replace_all` on the buttons.
class SlideFindReplaceRow extends StatelessWidget {
  /// Creates the row over [controller].
  const SlideFindReplaceRow({
    required this.controller,
    this.compact = false,
    super.key,
  });

  /// The find bar's state.
  final SlideFindController controller;

  /// Whether the bar is a phone's.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final field = SlideFindField(
      key: const ValueKey('slide_find_replacement'),
      controller: controller.replacement,
      label: 'Replace with',
      icon: QuarkIcons.find_replace,
      onSubmitted: controller.replaceCurrent,
    );
    final buttons = Wrap(
      alignment: WrapAlignment.end,
      spacing: tokens.spacingSm,
      children: [
        QuarkBarChip(
          key: const ValueKey('slide_find_replace'),
          icon: QuarkIcons.find_replace,
          label: 'Replace',
          tooltip: 'Replace this match',
          keepLabel: true,
          onPressed: controller.canReplace ? controller.replaceCurrent : null,
        ),
        QuarkBarChip(
          key: const ValueKey('slide_find_replace_all'),
          icon: QuarkIcons.find_replace,
          label: 'Replace all',
          tooltip: 'Replace every match',
          keepLabel: true,
          onPressed: controller.canStep ? controller.replaceAll : null,
        ),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: tokens.spacingXs,
        children: [field, buttons],
      );
    }
    return Row(
      spacing: tokens.spacingSm,
      children: [
        Expanded(child: field),
        buttons,
      ],
    );
  }
}
