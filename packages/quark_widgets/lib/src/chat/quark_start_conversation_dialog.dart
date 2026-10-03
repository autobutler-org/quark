import 'package:flutter/material.dart';

import '../core/quark_loader.dart';
import '../models/principal_item.dart';
import '../theme/quark_tokens.dart';
import '../users/principal_picker.dart';

/// Asks who to message privately (#2497): a sentence saying it makes a
/// private channel with just the two of you, a searchable list of people,
/// and a start button.
///
/// It does not close itself, and it decides nothing. The people, who is
/// picked, loading, and errors are the caller's: [people] and [selected]
/// in, [onSelected] out. [onStart] fires on the start button once someone
/// is picked; the caller makes or opens the channel and pops the dialog.
/// [loadError] stands in for the list when the people didn't load, and
/// [error] says why starting failed.
///
/// Key prefixes: `start_conversation_cancel` and `start_conversation_submit`
/// on the buttons, and `PrincipalPicker`'s `principal_search` and
/// `principal_option_user_<id>` on the list.
///
/// ```dart
/// showDialog<void>(
///   context: context,
///   builder: (ctx) => QuarkStartConversationDialog(
///     people: controller.people,
///     selected: picked,
///     isLoading: controller.isLoadingPeople,
///     onSelected: (person) => picked = person,
///     onStart: () => start(picked!),
///     onCancel: () => Navigator.of(ctx).pop(),
///   ),
/// );
/// ```
class QuarkStartConversationDialog extends StatelessWidget {
  /// Creates the dialog over [people].
  const QuarkStartConversationDialog({
    required this.people,
    required this.onSelected,
    required this.onStart,
    required this.onCancel,
    this.selected,
    this.isLoading = false,
    this.loadError,
    this.isSubmitting = false,
    this.error,
    super.key,
  });

  /// The accounts that can be messaged, in the order they are shown.
  final List<PrincipalItem> people;

  /// Called with the person tapped.
  final ValueChanged<PrincipalItem> onSelected;

  /// Called when the start button is tapped. The button is enabled only with
  /// [selected] set and nothing submitting.
  final VoidCallback onStart;

  /// Called when the cancel button is tapped.
  final VoidCallback onCancel;

  /// The person picked, marked in the list. Null picks no one.
  final PrincipalItem? selected;

  /// Whether the people are still loading. Shows a spinner in their place.
  final bool isLoading;

  /// A sentence saying why the people could not be loaded, composed by the
  /// caller. Shown in place of them.
  final String? loadError;

  /// Whether the conversation is being started. Disables both buttons.
  final bool isSubmitting;

  /// A sentence saying why starting failed, composed by the caller. Shown
  /// under the list.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final loadError = this.loadError;
    final error = this.error;

    return AlertDialog(
      scrollable: true,
      title: const Text('Message someone'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This starts a private channel with just the two of you, or '
              'opens the one you already have. You can add more people later '
              "from Members in the channel's settings.",
              style: TextStyle(color: tokens.mutedForeground),
            ),
            SizedBox(height: tokens.spacingMd),
            if (isLoading)
              Padding(
                padding: EdgeInsets.all(tokens.spacingLg),
                child: const Center(child: QuarkLoader()),
              )
            else if (loadError != null)
              Text(loadError, style: TextStyle(color: tokens.error))
            else if (people.isEmpty)
              const Text('No one else has an account on this Quark yet.')
            else
              PrincipalPicker(
                options: people,
                selected: selected,
                searchLabel: 'Search people',
                onSelected: onSelected,
              ),
            if (error != null) ...[
              SizedBox(height: tokens.spacingSm),
              Text(error, style: TextStyle(color: tokens.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('start_conversation_cancel'),
          onPressed: isSubmitting ? null : onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('start_conversation_submit'),
          onPressed: selected == null || isSubmitting ? null : onStart,
          child: isSubmitting
              ? const QuarkLoader(size: 20)
              : const Text('Message'),
        ),
      ],
    );
  }
}
