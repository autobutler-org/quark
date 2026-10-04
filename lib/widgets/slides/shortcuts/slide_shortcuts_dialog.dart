import 'package:flutter/material.dart';
import 'package:quark/utils/slide_shortcuts.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import 'slide_shortcut_section_view.dart';

/// The slides keyboard shortcuts (#1168): a searchable list grouped by
/// section, with each key combination drawn as key caps spelled for the
/// platform (Cmd on macOS and iOS, Ctrl elsewhere).
///
/// It reads [SlideShortcuts.all], so the list is whatever the table says.
/// Typing in the search box keeps the shortcuts whose name, section or keys
/// contain every word; a query that matches nothing says so. The list
/// scrolls, so it survives a phone and a 2.0 text scale.
///
/// Key prefixes: `slide_shortcuts_dialog` on the dialog,
/// `slide_shortcuts_search` on the search field, `slide_shortcuts_close` on
/// Close, `slide_shortcuts_empty` on the no-match message,
/// `slide_shortcut_section_<name>` on a section and `slide_shortcut_<id>` on
/// a row.
///
/// ```dart
/// SlideShortcutsDialog.show(context);
/// ```
class SlideShortcutsDialog extends StatefulWidget {
  /// A dialog spelled for [platform], or for the theme's platform when null.
  const SlideShortcutsDialog({this.platform, super.key});

  /// Whose key names to print; null follows the theme.
  final TargetPlatform? platform;

  /// Shows the dialog and completes when it is closed.
  static Future<void> show(BuildContext context, {TargetPlatform? platform}) =>
      showDialog<void>(
        context: context,
        builder: (_) => SlideShortcutsDialog(platform: platform),
      );

  @override
  State<SlideShortcutsDialog> createState() => _SlideShortcutsDialogState();
}

class _SlideShortcutsDialogState extends State<SlideShortcutsDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final platform = widget.platform ?? Theme.of(context).platform;
    final shown = SlideShortcuts.search(_search.text, platform);
    return Dialog(
      key: const ValueKey('slide_shortcuts_dialog'),
      insetPadding: EdgeInsets.all(tokens.spacingMd),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacingMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Keyboard shortcuts',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  QuarkBarIconButton(
                    key: const ValueKey('slide_shortcuts_close'),
                    icon: QuarkIcons.close,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              SizedBox(height: tokens.spacingSm),
              TextField(
                key: const ValueKey('slide_shortcuts_search'),
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(QuarkIcons.search),
                  hintText: 'Search shortcuts',
                ),
              ),
              Flexible(
                child: shown.isEmpty
                    ? Padding(
                        key: const ValueKey('slide_shortcuts_empty'),
                        padding: EdgeInsets.all(tokens.spacingLg),
                        child: Text(
                          'No shortcuts match "${_search.text.trim()}".',
                          style: TextStyle(color: tokens.mutedForeground),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final section in SlideShortcutSection.values)
                            if (shown.any((s) => s.section == section))
                              SlideShortcutSectionView(
                                section: section,
                                shortcuts: [
                                  for (final s in shown)
                                    if (s.section == section) s,
                                ],
                                platform: platform,
                              ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
