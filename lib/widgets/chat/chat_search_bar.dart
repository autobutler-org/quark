import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The search field above the open channel's messages (#2429), with a line
/// under it saying what was searched.
///
/// Chat is end-to-end encrypted, so the search runs on this device over the
/// messages it has loaded and decrypted, and the line says so rather than
/// reading as a search of the whole channel: [scopeText] before a query, then
/// how many loaded messages match. While [hasOlder], a button beside it loads
/// the page before the oldest, so the search reaches further back.
///
/// The caller holds the query: [onChanged] fires as it is typed, and the
/// caller filters the list and passes back [matchCount].
///
/// Keys: `chat_search_field` on the field, `chat_search_status` on the line
/// under it, `chat_search_load_older` on the button that loads older
/// messages, and `chat_search_close` on the close button.
class ChatSearchBar extends StatelessWidget {
  /// Creates the bar, reporting [matchCount] matches.
  const ChatSearchBar({
    required this.matchCount,
    required this.hasOlder,
    required this.isLoadingOlder,
    required this.onChanged,
    required this.onLoadOlder,
    required this.onClose,
    super.key,
  });

  /// What the line under the field says before anything is typed.
  static const scopeText =
      'Search runs on this device, over the messages loaded here. The Quark '
      'never sees what you search for.';

  static const _loaded = ' in the messages loaded on this device.';

  /// How many loaded messages match; null with nothing typed.
  final int? matchCount;

  /// Whether the channel may hold messages older than the ones loaded.
  final bool hasOlder;

  /// Whether a page of older messages is loading.
  final bool isLoadingOlder;

  /// Fires with the query as it is typed.
  final ValueChanged<String> onChanged;

  /// Loads the page of messages before the oldest loaded.
  final VoidCallback onLoadOlder;

  /// Closes the search.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacingMd,
        vertical: tokens.spacingXs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('chat_search_field'),
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: onChanged,
                  decoration: const InputDecoration(
                    hintText: 'Search this channel',
                    prefixIcon: Icon(QuarkIcons.search, size: 20),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacingSm),
              QuarkBarIconButton(
                key: const ValueKey('chat_search_close'),
                icon: QuarkIcons.close,
                tooltip: 'Close search',
                onPressed: onClose,
              ),
            ],
          ),
          // A Wrap, so on a phone the button drops under the line instead of
          // squeezing it.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: tokens.spacingSm,
            children: [
              Text(
                switch (matchCount) {
                  null => scopeText,
                  0 => 'No matches$_loaded',
                  1 => '1 match$_loaded',
                  final count => '$count matches$_loaded',
                },
                key: const ValueKey('chat_search_status'),
                style: TextStyle(color: tokens.mutedForeground, fontSize: 12),
              ),
              if (hasOlder)
                TextButton(
                  key: const ValueKey('chat_search_load_older'),
                  onPressed: isLoadingOlder ? null : onLoadOlder,
                  child: isLoadingOlder
                      ? const QuarkLoader(size: 16)
                      : const Text('Load older messages'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
