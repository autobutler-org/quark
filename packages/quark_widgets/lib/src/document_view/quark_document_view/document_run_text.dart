import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';
import '../quark_document.dart';
import 'document_link.dart';

/// Styled runs in one document paragraph, heading, or list item.
class DocumentRunText extends StatelessWidget {
  /// Creates run text.
  const DocumentRunText({
    required this.runs,
    required this.style,
    this.textAlign = TextAlign.start,
    this.onLinkTap,
    super.key,
  });

  /// Runs in source order.
  final List<QuarkDocumentRun> runs;

  /// The paragraph's base style.
  final TextStyle style;

  /// The paragraph's horizontal alignment.
  final TextAlign textAlign;

  /// Called with a link target when it is tapped.
  final ValueChanged<String>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Text.rich(
      TextSpan(
        children: [
          for (final run in runs)
            if (run.link case final href?)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: DocumentLink(
                  key: ValueKey('document_link_${run.linkIndex}'),
                  href: href,
                  onTap: onLinkTap,
                  child: Text(
                    run.text,
                    style: _style(run, tokens).copyWith(
                      color: tokens.primary,
                      decoration: TextDecoration.combine([
                        TextDecoration.underline,
                        if (run.strike) TextDecoration.lineThrough,
                      ]),
                      decorationColor: tokens.primary,
                    ),
                  ),
                ),
              )
            else
              TextSpan(text: run.text, style: _style(run, tokens)),
        ],
      ),
      textAlign: textAlign,
    );
  }

  TextStyle _style(QuarkDocumentRun run, QuarkTokens tokens) {
    final decorations = <TextDecoration>[
      if (run.underline) TextDecoration.underline,
      if (run.strike) TextDecoration.lineThrough,
    ];
    final raisedOrLowered = run.superscript || run.subscript;
    return style.copyWith(
      fontWeight: run.bold ? FontWeight.bold : null,
      fontStyle: run.italic ? FontStyle.italic : null,
      fontFamily: run.code ? 'monospace' : null,
      backgroundColor: run.code ? tokens.card : null,
      decoration: decorations.isEmpty
          ? null
          : TextDecoration.combine(decorations),
      fontSize: raisedOrLowered && style.fontSize != null
          ? style.fontSize! * 0.75
          : null,
      fontFeatures: run.superscript
          ? const [FontFeature.enable('sups')]
          : run.subscript
          ? const [FontFeature.enable('subs')]
          : null,
    );
  }
}
