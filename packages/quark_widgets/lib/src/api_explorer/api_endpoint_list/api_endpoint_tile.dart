import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../core/quark_tint_badge.dart';
import '../../markdown/quark_markdown_view/markdown_inline_spans.dart';
import '../../models/api_endpoint_item.dart';
import '../../theme/quark_tokens.dart';

/// One endpoint of `ApiEndpointList`: a header row with the method badge,
/// path, summary and markers, and [child] under it while [expanded].
///
/// The method is colored from the tokens the way the Swagger UI colors it:
/// GET in the accent, POST in success, PUT and PATCH in warning, DELETE in
/// error. The word is always drawn, so color only repeats it.
///
/// Key prefixes: `api_endpoint_<id>` on the header row.
class ApiEndpointTile extends StatelessWidget {
  /// Creates the row for [endpoint].
  const ApiEndpointTile({
    required this.endpoint,
    required this.expanded,
    required this.onTap,
    this.child,
    super.key,
  });

  /// The endpoint shown.
  final ApiEndpointItem endpoint;

  /// Whether the row is open, which flips its chevron.
  final bool expanded;

  /// Called when the header row is tapped.
  final VoidCallback onTap;

  /// What the open row shows under its header. Null shows nothing.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final method = endpoint.method.toUpperCase();
    final methodColor = switch (method) {
      'GET' => tokens.primary,
      'POST' => tokens.success,
      'PUT' || 'PATCH' => tokens.warning,
      'DELETE' => tokens.error,
      _ => tokens.secondaryForeground,
    };
    final markers = [
      if (!endpoint.inSwagger) ('Not in Swagger', tokens.error),
      if (endpoint.callers.isEmpty)
        ('No client caller', tokens.secondaryForeground),
    ];
    final child = this.child;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: expanded ? methodColor : tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: expanded,
            child: ListTile(
              key: ValueKey('api_endpoint_${endpoint.id}'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusMd),
              ),
              leading: SizedBox(
                width: 72,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: QuarkTintBadge(label: method, color: methodColor),
                ),
              ),
              title: Text(
                endpoint.path,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: markdownMonoFamily,
                  fontFamilyFallback: markdownMonoFallback,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: endpoint.summary.isEmpty && markers.isEmpty
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: tokens.spacingXs,
                      children: [
                        if (endpoint.summary.isNotEmpty) Text(endpoint.summary),
                        if (markers.isNotEmpty)
                          Wrap(
                            spacing: tokens.spacingXs,
                            runSpacing: tokens.spacingXs,
                            children: [
                              for (final (label, color) in markers)
                                QuarkTintBadge(
                                  label: label,
                                  color: color,
                                  dense: true,
                                ),
                            ],
                          ),
                      ],
                    ),
              trailing: Icon(
                expanded ? QuarkIcons.expand_less : QuarkIcons.expand_more,
              ),
              onTap: onTap,
            ),
          ),
          if (expanded && child != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                tokens.spacingMd,
                0,
                tokens.spacingMd,
                tokens.spacingMd,
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}
