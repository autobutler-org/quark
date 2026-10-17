import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';
import '../quark_markdown_document.dart';
import '../quark_markdown_view.dart';
import 'markdown_flow.dart';

/// A GitHub alert (`> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`,
/// `[!CAUTION]`) in a `QuarkMarkdownView`: a callout with a colored left
/// edge, a faint tint of the same color, and its kind's icon and title above
/// the body.
///
/// [alert] is the `div` the parser makes of one: its first child is the
/// title paragraph and the rest is the body. Note and Important take the
/// primary color, Tip success, Warning warning and Caution error.
///
/// Key prefixes: none of its own. The view keys each alert
/// `markdown_alert_<n>`.
///
/// ```dart
/// MarkdownAlert(alert: node, style: bodyStyle);
/// ```
class MarkdownAlert extends StatelessWidget {
  /// Creates the callout for [alert].
  const MarkdownAlert({
    required this.alert,
    required this.style,
    this.onLinkTap,
    this.imageBuilder,
    super.key,
  });

  /// The alert's `div`, as `QuarkMarkdownDocument.parse` made it.
  final md.Element alert;

  /// The body text style. The title derives its own from it.
  final TextStyle style;

  /// Called with a link's raw `href` when it is tapped; null leaves links
  /// inert.
  final ValueChanged<String>? onLinkTap;

  /// Builds each image from its raw `src` and `alt`; null shows a
  /// placeholder.
  final QuarkMarkdownImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final quark = QuarkTokens.of(context);
    final (color, icon) = switch (markdownAlertKind(alert)) {
      'tip' => (quark.success, QuarkIcons.light_mode_outlined),
      'important' => (quark.primary, QuarkIcons.star_border),
      'warning' => (quark.warning, QuarkIcons.warning_amber),
      'caution' => (quark.error, QuarkIcons.error_outline),
      _ => (quark.primary, QuarkIcons.info_outline),
    };
    final children = alert.children ?? const <md.Node>[];
    final body = children.skip(1).toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Padding(
        padding: EdgeInsets.all(quark.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: quark.spacingSm,
          children: [
            Row(
              spacing: quark.spacingSm,
              children: [
                Icon(icon, size: (style.fontSize ?? 16) * 1.2, color: color),
                Flexible(
                  child: Text(
                    children.firstOrNull?.textContent ?? '',
                    style: style.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (body.isNotEmpty)
              MarkdownFlow(
                nodes: body,
                style: style,
                onLinkTap: onLinkTap,
                imageBuilder: imageBuilder,
              ),
          ],
        ),
      ),
    );
  }
}
