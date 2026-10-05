import 'package:flutter/material.dart';
import 'package:quark/services/slides_service.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What a PowerPoint import left out or simplified, shown before the new
/// presentation opens (#1171).
///
/// The Quark sends one warning per kind of thing per slide; this lists each
/// kind once, with the slides it was on, so a deck with a chart on every
/// slide reads as one line rather than forty. Closing it — the button, Esc
/// or a tap outside — opens the presentation either way: the import has
/// already happened.
///
/// Key prefixes: `slides_import_summary` on the dialog,
/// `slides_import_summary_open` on its button, `slides_import_warning_<i>`
/// on each line, in order.
///
/// ```dart
/// await PowerPointImportSummaryDialog.show(context, result);
/// ```
class PowerPointImportSummaryDialog extends StatelessWidget {
  /// A summary of [result].
  const PowerPointImportSummaryDialog({required this.result, super.key});

  /// The import to summarize.
  final PowerPointImport result;

  /// Shows the summary and completes once it is closed.
  static Future<void> show(BuildContext context, PowerPointImport result) =>
      showDialog<void>(
        context: context,
        builder: (_) => PowerPointImportSummaryDialog(result: result),
      );

  /// Each warning's message once, in the order they first came, with the
  /// slides it was on in ascending order; 0 stands for the whole deck.
  static List<({String message, List<int> slides})> grouped(
    List<PowerPointImportWarning> warnings,
  ) {
    final slides = <String, Set<int>>{};
    for (final w in warnings) {
      if (w.message.trim().isEmpty) continue;
      (slides[w.message.trim()] ??= {}).add(w.slide);
    }
    return [
      for (final MapEntry(key: message, value: on) in slides.entries)
        (message: message, slides: on.toList()..sort()),
    ];
  }

  /// Where a warning applied, as "Slide 2", "Slides 2, 5 and 9" or "Whole
  /// presentation".
  static String where(List<int> slides) {
    final numbers = [
      for (final s in slides)
        if (s > 0) '$s',
    ];
    if (numbers.isEmpty) return 'Whole presentation';
    if (numbers.length == 1) return 'Slide ${numbers.single}';
    final last = numbers.removeLast();
    return 'Slides ${numbers.join(', ')} and $last';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final groups = grouped(result.warnings);
    final count = groups.length;
    final slides = result.slides == 1 ? '1 slide' : '${result.slides} slides';
    return AlertDialog(
      key: const ValueKey('slides_import_summary'),
      // A long list at a large text size scrolls with its title, rather than
      // pinning a title that leaves no room for it.
      scrollable: true,
      icon: Icon(QuarkIcons.info_outline, color: tokens.mutedForeground),
      title: Text(
        count == 1
            ? '1 kind of content was left out or simplified'
            : '$count kinds of content were left out or simplified',
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'The presentation has $slides. Some of the PowerPoint file '
              "uses features the editor doesn't have yet:",
            ),
            for (final (i, g) in groups.indexed)
              Padding(
                key: ValueKey('slides_import_warning_$i'),
                padding: EdgeInsets.only(top: tokens.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.message, style: theme.textTheme.bodyMedium),
                    Text(
                      where(g.slides),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(height: tokens.spacingMd),
            Text(
              'The PowerPoint file itself is unchanged.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.mutedForeground,
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('slides_import_summary_open'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Open presentation'),
        ),
      ],
    );
  }
}
