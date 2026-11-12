import 'package:flutter/material.dart';

import '../../markdown/quark_markdown_view/markdown_inline_spans.dart';
import '../../theme/quark_tokens.dart';

/// A schema, header list or response body of `ApiEndpointDetails`:
/// selectable monospace [text] on a tinted panel that scrolls both ways, so
/// a long line never wraps and a long body never pushes the page away.
///
/// Key prefixes: none. The caller keys it.
class ApiCodeBlock extends StatelessWidget {
  /// Creates a panel showing [text].
  const ApiCodeBlock({required this.text, super.key});

  /// What the panel shows, as given.
  final String text;

  /// The tallest the panel grows before it scrolls.
  static const double maxHeight = 320;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final style = Theme.of(context).textTheme.bodySmall;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: maxHeight),
        // ponytail: one paragraph laid out whole. The caller caps a body at
        // about 64 KiB; much more wants a lazy list of lines like the code
        // viewer's.
        child: SingleChildScrollView(
          padding: EdgeInsets.all(tokens.spacingSm),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // Selectable text is a target, so it gets the 48dp a button does.
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: kMinInteractiveDimension,
              ),
              child: SelectableText(
                text,
                style: style?.copyWith(
                  fontFamily: markdownMonoFamily,
                  fontFamilyFallback: markdownMonoFallback,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
