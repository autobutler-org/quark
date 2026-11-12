import 'package:material_ui/material_ui.dart';

import '../theme/quark_tokens.dart';

/// Asks which occurrences move when a drag or a key press lands on a
/// repeating event (#3215).
///
/// "This event" moves only the occurrence that was dragged. "This and
/// following" moves that one and every one after it. "All events" moves the
/// whole series. Cancel leaves it where it was.
///
/// It does not close itself: the callbacks fire, and the caller that pushed
/// the dialog pops it. The copy and the buttons scroll when the window is
/// too short for them, so the choices stay reachable on a phone and at large
/// text.
///
/// Key prefixes: `calendar_move_this`, `calendar_move_following`,
/// `calendar_move_all`, and `calendar_move_cancel`.
///
/// ```dart
/// showDialog<void>(
///   context: context,
///   builder: (ctx) => CalendarMoveSeriesDialog(
///     title: 'Soccer practice',
///     onThisEvent: () => Navigator.of(ctx).pop(),
///     onThisAndFollowing: () => Navigator.of(ctx).pop(),
///     onAllEvents: () => Navigator.of(ctx).pop(),
///     onCancel: () => Navigator.of(ctx).pop(),
///   ),
/// );
/// ```
class CalendarMoveSeriesDialog extends StatelessWidget {
  /// Creates the question for the event titled [title].
  const CalendarMoveSeriesDialog({
    required this.title,
    required this.onThisEvent,
    required this.onThisAndFollowing,
    required this.onAllEvents,
    required this.onCancel,
    super.key,
  });

  /// The repeating event's title.
  final String title;

  /// Called when "This event" is tapped.
  final VoidCallback onThisEvent;

  /// Called when "This and following" is tapped.
  final VoidCallback onThisAndFollowing;

  /// Called when "All events" is tapped.
  final VoidCallback onAllEvents;

  /// Called when "Cancel" is tapped.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(
        title.isEmpty ? 'Move this repeating event?' : 'Move $title?',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('This event repeats. Choose which ones move.'),
          SizedBox(height: tokens.spacingMd),
          FilledButton(
            key: const ValueKey('calendar_move_this'),
            onPressed: onThisEvent,
            child: const Text('This event'),
          ),
          SizedBox(height: tokens.spacingSm),
          FilledButton(
            key: const ValueKey('calendar_move_following'),
            autofocus: true,
            onPressed: onThisAndFollowing,
            child: const Text('This and following'),
          ),
          SizedBox(height: tokens.spacingSm),
          FilledButton(
            key: const ValueKey('calendar_move_all'),
            onPressed: onAllEvents,
            child: const Text('All events'),
          ),
          SizedBox(height: tokens.spacingSm),
          TextButton(
            key: const ValueKey('calendar_move_cancel'),
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
