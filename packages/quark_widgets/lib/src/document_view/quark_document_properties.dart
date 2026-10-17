import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';
import 'document_properties.dart';
import 'quark_document_properties/document_property_row.dart';

/// The body of a document Properties sheet.
///
/// It shows only values the caller provides. Counts marked `saved` are
/// identified as the authoring application's last saved values; counts marked
/// `parsed` are identified as coming from the current preview.
///
/// Key prefixes: `document_property_<name>` on each row and
/// `document_properties_retry` on the error action.
///
/// ```dart
/// QuarkDocumentProperties(
///   properties: controller.properties,
///   isLoading: controller.isLoadingProperties,
///   error: controller.propertiesError,
///   onRetry: controller.loadProperties,
/// );
/// ```
class QuarkDocumentProperties extends StatelessWidget {
  /// Creates a properties sheet body.
  const QuarkDocumentProperties({
    this.properties,
    this.isLoading = false,
    this.error,
    this.onRetry,
    super.key,
  });

  /// The properties to show; null before they load.
  final DocumentProperties? properties;

  /// Whether properties are loading for the first time.
  final bool isLoading;

  /// The caller-composed load error; null when loading succeeded.
  final String? error;

  /// Called when Retry is tapped. Null leaves the button out.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final properties = this.properties;
    final error = this.error;
    final onRetry = this.onRetry;
    if (isLoading && properties == null) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: const Center(child: QuarkLoader()),
      );
    }
    if (error != null && properties == null) {
      return EmptyStateWidget(
        icon: QuarkIcons.error_outline,
        headline: error,
        action: onRetry == null
            ? null
            : FilledButton(
                key: const ValueKey('document_properties_retry'),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
      );
    }
    if (properties == null || properties.isEmpty) {
      return const EmptyStateWidget(
        icon: QuarkIcons.info_outline,
        headline: 'No document properties',
      );
    }

    final rows = <(String, String, String)>[
      if (properties.title case final value?) ('title', 'Title', value),
      if (properties.author case final value?) ('author', 'Author', value),
      if (properties.subject case final value?) ('subject', 'Subject', value),
      if (properties.created case final value?)
        ('created', 'Created', _date(context, value)),
      if (properties.modified case final value?)
        ('modified', 'Modified', _date(context, value)),
      if (properties.pages case final value?) ('pages', 'Pages', '$value'),
      if (properties.words case final value?) ('words', 'Words', '$value'),
      if (properties.characters case final value?)
        ('characters', 'Characters', '$value'),
      if (properties.slides case final value?) ('slides', 'Slides', '$value'),
      if (properties.sheets case final value?) ('sheets', 'Sheets', '$value'),
      if (properties.application case final value?)
        ('application', 'Application', value),
    ];
    final countsNote = switch (properties.countsSource) {
      'saved' when properties.application != null =>
        'Counts as last saved in ${properties.application}.',
      'saved' => 'Counts as last saved.',
      'parsed' => 'Counts from this preview.',
      _ => null,
    };
    return Column(
      key: const ValueKey('document_properties'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null)
          Padding(
            padding: EdgeInsets.only(bottom: tokens.spacingSm),
            child: Text(error, style: TextStyle(color: tokens.error)),
          ),
        for (final (key, label, value) in rows)
          DocumentPropertyRow(
            key: ValueKey('document_property_$key'),
            label: label,
            value: value,
          ),
        if (countsNote != null)
          Padding(
            key: const ValueKey('document_property_counts_source'),
            padding: EdgeInsets.only(top: tokens.spacingSm),
            child: Text(
              countsNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }

  String _date(BuildContext context, DateTime value) {
    final localizations = MaterialLocalizations.of(context);
    final local = value.toLocal();
    return '${localizations.formatMediumDate(local)}, '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
}
