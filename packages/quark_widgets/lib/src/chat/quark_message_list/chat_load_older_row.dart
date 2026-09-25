import 'package:flutter/material.dart';

import '../../core/quark_loader.dart';
import '../../theme/quark_tokens.dart';

/// The row at the top of a message list: a spinner while older messages
/// load, the error and a retry when they could not, or a button to load them
/// when there are more.
///
/// Renders nothing when there is nothing older to load.
///
/// A part of `QuarkMessageList`, tested through it.
///
/// Key prefixes: `message_list_load_older` on the load button and
/// `message_list_retry` on the retry button.
class ChatLoadOlderRow extends StatelessWidget {
  /// Creates the row.
  const ChatLoadOlderRow({
    required this.isLoading,
    required this.hasMore,
    this.error,
    this.onLoadOlder,
    super.key,
  });

  /// Whether older messages are loading.
  final bool isLoading;

  /// Whether there are older messages than the ones shown.
  final bool hasMore;

  /// Why older messages could not be loaded, composed by the caller.
  final String? error;

  /// Asks for older messages. Also the retry after an [error]; null shows
  /// no retry.
  final VoidCallback? onLoadOlder;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;

    if (isLoading) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: const Center(child: QuarkLoader(size: 20)),
      );
    }
    if (error != null) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: Column(
          children: [
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.error),
            ),
            if (onLoadOlder != null)
              TextButton(
                key: const ValueKey('message_list_retry'),
                onPressed: onLoadOlder,
                child: const Text('Try again'),
              ),
          ],
        ),
      );
    }
    if (!hasMore) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.all(tokens.spacingSm),
      child: Center(
        child: TextButton(
          key: const ValueKey('message_list_load_older'),
          onPressed: onLoadOlder,
          child: const Text('Load older messages'),
        ),
      ),
    );
  }
}
