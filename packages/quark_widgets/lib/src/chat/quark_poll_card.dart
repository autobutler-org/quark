import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../calendar/calendar_labels.dart';
import '../core/quark_tint_badge.dart';
import '../models/chat_poll_answer.dart';
import '../models/chat_poll_item.dart';
import '../models/chat_poll_type.dart';
import '../theme/quark_tokens.dart';
import 'quark_poll_card/poll_option_tally.dart';

/// A chat poll: its question, a way to answer it, and the tally so far.
///
/// A `single` poll offers its options as radio buttons, a `multiple` poll as
/// checkboxes, and a `text` poll a text field of at most [maxTextLength]
/// characters. Picking or typing is only the reader's pending answer, held
/// here the way a text field holds its text; "Answer" (or "Change answer")
/// hands it to [onAnswer], and the caller's next [ChatPollItem.myAnswer]
/// replaces it.
///
/// The reader can answer while [onAnswer] is set, the poll is open, and they
/// have not answered yet or [ChatPollItem.allowChange] lets them change it.
/// Otherwise the inputs are drawn disabled with their own answer, if any.
///
/// Each option shows its share of [ChatPollItem.responseCount] under it, and
/// a `text` poll lists the written answers, while
/// [ChatPollItem.resultsVisible] holds. When it does not, as for a
/// results-after-close poll still open, a line says the results come once
/// the poll closes. The header names the poll anonymous when it is, and says
/// when it closes or that it has closed.
///
/// "Close poll" fires [onClose] and is offered only while [onClose] is set
/// and the poll is open; the caller sets it for the author. "Export" fires
/// [onExport] and is offered only while [onExport] is set and the results
/// are visible.
///
/// Key prefixes, with [id]: `poll_option_<id>_<index>` on each option,
/// `poll_tally_<id>_<index>` on its tally, `poll_text_<id>` on the text
/// field, `poll_text_answer_<id>_<index>` on each written answer,
/// `poll_results_hidden_<id>` on the results-after-close line,
/// `poll_anonymous_<id>` and `poll_closed_<id>` (or `poll_closes_<id>`) on
/// the header's badges, and `poll_answer_<id>`, `poll_close_<id>` and
/// `poll_export_<id>` on the buttons.
///
/// ```dart
/// QuarkPollCard(
///   id: message.id,
///   poll: message.poll!,
///   onAnswer: (answer) => controller.answerPoll(message.id, answer),
///   onClose: isAuthor ? () => controller.closePoll(message.id) : null,
///   onExport: () => exportPoll(message.id),
/// );
/// ```
class QuarkPollCard extends StatefulWidget {
  /// Creates the card for [poll].
  const QuarkPollCard({
    required this.id,
    required this.poll,
    this.onAnswer,
    this.onClose,
    this.onExport,
    super.key,
  });

  /// The poll message's id, which the keys carry.
  final String id;

  /// The poll to draw.
  final ChatPollItem poll;

  /// Called with the reader's answer. Null draws the inputs disabled.
  final ValueChanged<ChatPollAnswer>? onAnswer;

  /// Closes the poll. Null leaves "Close poll" out.
  final VoidCallback? onClose;

  /// Exports the results. Null leaves "Export" out.
  final VoidCallback? onExport;

  /// The longest written answer, in characters. An answer is padded to
  /// 4 KiB before it is encrypted, and a thousand characters of up to four
  /// UTF-8 bytes each fit with room for the JSON around them.
  static const int maxTextLength = 1000;

  @override
  State<QuarkPollCard> createState() => _QuarkPollCardState();
}

/// The reader's pending answer: the options picked, or null for none picked
/// since [ChatPollItem.myAnswer] last changed, and the text being written.
class _QuarkPollCardState extends State<QuarkPollCard> {
  List<int>? _choices;
  late final TextEditingController _text = TextEditingController(
    text: widget.poll.myAnswer?.text ?? '',
  );

  @override
  void didUpdateWidget(QuarkPollCard old) {
    super.didUpdateWidget(old);
    final mine = widget.poll.myAnswer;
    if (mine == old.poll.myAnswer) return;
    _choices = null;
    if (_text.text != (mine?.text ?? '')) _text.text = mine?.text ?? '';
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final id = widget.id;
    final poll = widget.poll;
    final mine = poll.myAnswer;
    final onAnswer = widget.onAnswer;
    final onClose = widget.onClose;
    final onExport = widget.onExport;
    final canAnswer =
        onAnswer != null &&
        !poll.isClosed &&
        (mine == null || poll.allowChange);
    final choices = _choices ?? mine?.choices ?? const <int>[];
    final pending = poll.type == ChatPollType.text
        ? ChatPollAnswer(text: _text.text)
        : ChatPollAnswer(choices: choices);
    final closesAt = poll.closesAt;
    final muted = TextStyle(color: tokens.mutedForeground, fontSize: 12);
    final showResults = poll.resultsVisible;

    void pick(int index, bool on) => setState(
      () => _choices = poll.type == ChatPollType.single
          ? [index]
          : ([...choices.where((c) => c != index), if (on) index]..sort()),
    );
    Widget? tallyOf(int index) => showResults
        ? PollOptionTally(
            key: ValueKey('poll_tally_${id}_$index'),
            count: poll.countAt(index),
            total: poll.responseCount,
          )
        : null;

    final options = [
      for (final (index, option) in poll.options.indexed)
        if (poll.type == ChatPollType.single)
          RadioListTile<int>(
            key: ValueKey('poll_option_${id}_$index'),
            value: index,
            enabled: canAnswer,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(option),
            subtitle: tallyOf(index),
          )
        else
          CheckboxListTile(
            key: ValueKey('poll_option_${id}_$index'),
            value: choices.contains(index),
            onChanged: canAnswer ? (on) => pick(index, on ?? false) : null,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(option),
            subtitle: tallyOf(index),
          ),
    ];

    // A Material, not a DecoratedBox, so the option tiles' ink shows on it.
    return Material(
      color: tokens.card,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: tokens.spacingSm,
          children: [
            Wrap(
              spacing: tokens.spacingSm,
              runSpacing: tokens.spacingXs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: tokens.spacingXs,
                  children: [
                    Icon(QuarkIcons.poll, size: 16, color: tokens.primary),
                    Text('Poll', style: muted),
                  ],
                ),
                if (poll.anonymous)
                  QuarkTintBadge(
                    key: ValueKey('poll_anonymous_$id'),
                    label: 'Anonymous',
                    semanticLabel: 'Anonymous poll: nobody sees who answered',
                    dense: true,
                  ),
                if (poll.isClosed)
                  QuarkTintBadge(
                    key: ValueKey('poll_closed_$id'),
                    label: 'Closed',
                    color: tokens.mutedForeground,
                    dense: true,
                  )
                else if (closesAt != null)
                  Text(
                    'Closes ${CalendarLabels.date(closesAt)}, '
                    '${CalendarLabels.time(closesAt, use24Hour: MediaQuery.alwaysUse24HourFormatOf(context))}',
                    key: ValueKey('poll_closes_$id'),
                    style: muted,
                  ),
              ],
            ),
            Text(
              poll.prompt,
              style: TextStyle(
                color: tokens.foreground,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            if (poll.type == ChatPollType.single)
              RadioGroup<int>(
                groupValue: choices.isEmpty ? null : choices.first,
                onChanged: (index) {
                  if (index != null) pick(index, true);
                },
                child: Column(children: options),
              )
            else if (poll.type == ChatPollType.multiple)
              Column(children: options)
            else ...[
              TextField(
                key: ValueKey('poll_text_$id'),
                controller: _text,
                enabled: canAnswer,
                maxLength: QuarkPollCard.maxTextLength,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Write your answer',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (showResults)
                for (final (index, answer) in poll.textAnswers.indexed)
                  Text(
                    answer,
                    key: ValueKey('poll_text_answer_${id}_$index'),
                    style: TextStyle(color: tokens.foreground),
                  ),
            ],
            if (!showResults)
              Row(
                key: ValueKey('poll_results_hidden_$id'),
                spacing: tokens.spacingXs,
                children: [
                  Icon(
                    QuarkIcons.visibility_off_outlined,
                    size: 14,
                    color: tokens.mutedForeground,
                  ),
                  Flexible(
                    child: Text(
                      'Results appear when the poll closes.',
                      style: muted,
                    ),
                  ),
                ],
              ),
            Wrap(
              spacing: tokens.spacingSm,
              runSpacing: tokens.spacingXs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  poll.responseCount == 1
                      ? '1 response'
                      : '${poll.responseCount} responses',
                  style: muted,
                ),
                if (canAnswer)
                  FilledButton(
                    key: ValueKey('poll_answer_$id'),
                    onPressed: pending.isEmpty || pending == mine
                        ? null
                        : () => onAnswer(pending),
                    child: Text(mine == null ? 'Answer' : 'Change answer'),
                  ),
                if (onClose != null && !poll.isClosed)
                  TextButton.icon(
                    key: ValueKey('poll_close_$id'),
                    onPressed: onClose,
                    icon: const Icon(QuarkIcons.lock_outline, size: 18),
                    label: const Text('Close poll'),
                  ),
                if (onExport != null && showResults)
                  TextButton.icon(
                    key: ValueKey('poll_export_$id'),
                    onPressed: onExport,
                    icon: const Icon(QuarkIcons.download_outlined, size: 18),
                    label: const Text('Export'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
