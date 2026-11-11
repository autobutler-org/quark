import 'package:flutter/material.dart';

import '../../../models/quark_menu_entry.dart';
import '../../../theme/quark_tokens.dart';

/// The actions under a message in `ChatMessageContextMenu`: every one of
/// [entries] in full, as 48dp rows on a card of `QuarkTokens.card`, with a
/// destructive entry in `QuarkTokens.error`.
///
/// A tap on a row fires [onSelected] with that entry's `onSelected`, so the
/// menu can close before it runs, as `showQuarkMenu` does. An entry with no
/// `onSelected` is drawn disabled, and a divider is a thin rule.
///
/// A part of `ChatMessageRow`, tested through `QuarkMessageList`.
///
/// Key prefixes: none of its own; each row carries its entry's `key`.
class ChatContextMenuActions extends StatelessWidget {
  /// Creates the list of [entries].
  const ChatContextMenuActions({
    required this.entries,
    required this.onSelected,
    super.key,
  });

  /// The rows, in order.
  final List<QuarkMenuEntry> entries;

  /// Called with the chosen entry's `onSelected`.
  final ValueChanged<VoidCallback> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Material(
      color: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in entries)
                if (entry.isDivider)
                  Divider(height: 1, color: tokens.border)
                else
                  InkWell(
                    key: entry.key,
                    onTap: switch (entry.onSelected) {
                      final run? => () => onSelected(run),
                      null => null,
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: kMinInteractiveDimension,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: tokens.spacingMd,
                        ),
                        child: Row(
                          children: [
                            if (entry.icon != null) ...[
                              Icon(
                                entry.icon,
                                size: 20,
                                color: entry.destructive
                                    ? tokens.error
                                    : tokens.foreground,
                              ),
                              SizedBox(width: tokens.spacingMd),
                            ],
                            Flexible(
                              child: Text(
                                entry.label,
                                style: TextStyle(
                                  color: entry.destructive
                                      ? tokens.error
                                      : tokens.foreground,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
