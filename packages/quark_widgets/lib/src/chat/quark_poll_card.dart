import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../calendar/calendar_labels.dart';
import '../core/quark_tint_badge.dart';
import '../models/chat_poll_answer.dart';
import '../models/chat_poll_item.dart';
import '../models/chat_poll_type.dart';
import '../theme/quark_tokens.dart';
import 'quark_poll_card/poll_question_body.dart';

/// A chat poll: its questions, a way to answer them, and the tally so far.
///
/// A `single` question offers its options as radio buttons, a `multiple`
/// question as checkboxes, a `text` question a text field of at most
/// [maxTextLength] characters, a `number` question a number field, a `date`
/// question a date button, and a `rating` question a row of stars. Picking
/// or typing is only the reader's pending answer, held here the way a text
/// field holds its text; "Answer" (or "Change answer") hands the whole poll
/// to [onAnswer], and the caller's next [ChatPollItem.myAnswer] replaces it.
/// A poll with several questions sends one answer per question, in
/// [ChatPollAnswer.parts].
///
/// The reader can answer while [onAnswer] is set, the poll is open, and they
/// have not answered yet or [ChatPollItem.allowChange] lets them change it.
/// Otherwise the inputs are drawn disabled with their own answer, if any.
/// Every question has to be answered before the button enables.
///
/// Each option shows its share of [ChatPollItem.responseCount] under it, a
/// `text`, `number` or `date` question lists its answers, and a `rating`
/// question shows how many answers gave each step, while
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
/// Key prefixes, with [id]. A poll with one question uses these as written.
/// A poll with more inserts `_q<index>` (the question, from 0) after the
/// name: `poll_option_<id>_<index>` on each option, `poll_tally_<id>_<index>`
/// on its tally, `poll_text_<id>` on the text field,
/// `poll_text_answer_<id>_<index>` on each written answer,
/// `poll_number_<id>` on the number field, `poll_number_average_<id>` on its
/// average, `poll_date_<id>` on the date button, `poll_rating_<id>_<step>`
/// on each star and `poll_rating_tally_<id>_<step>` on that step's tally,
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

/// The reader's pending answer for each question: a null slot follows
/// [ChatPollItem.myAnswer], and a text controller holds text or a number.
class _QuarkPollCardState extends State<QuarkPollCard> {
  final List<List<int>?> _choices = [];
  final List<TextEditingController> _fields = [];
  final List<String?> _dates = [];
  final List<int?> _ratings = [];

  @override
  void initState() {
    super.initState();
    _ensureSlots();
    _applyAnswerText();
  }

  @override
  void didUpdateWidget(QuarkPollCard old) {
    super.didUpdateWidget(old);
    final grew = _ensureSlots();
    if (widget.poll.myAnswer == old.poll.myAnswer && !grew) return;
    if (widget.poll.myAnswer != old.poll.myAnswer) {
      for (var i = 0; i < _choices.length; i++) {
        _choices[i] = null;
        _dates[i] = null;
        _ratings[i] = null;
      }
    }
    _applyAnswerText();
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  /// Grows or shrinks the pending slots to the poll's questions. True when
  /// the count changed.
  bool _ensureSlots() {
    final count = widget.poll.shownQuestions.length;
    final grew = _fields.length != count;
    while (_fields.length < count) {
      _fields.add(TextEditingController());
      _choices.add(null);
      _dates.add(null);
      _ratings.add(null);
    }
    while (_fields.length > count) {
      _fields.removeLast().dispose();
      _choices.removeLast();
      _dates.removeLast();
      _ratings.removeLast();
    }
    return grew;
  }

  void _applyAnswerText() {
    final questions = widget.poll.shownQuestions;
    for (var i = 0; i < questions.length; i++) {
      final mine = questions[i].myAnswer;
      final shown = switch (questions[i].type) {
        ChatPollType.text => mine?.text ?? '',
        ChatPollType.number => mine?.number ?? '',
        _ => '',
      };
      if (_fields[i].text != shown) _fields[i].text = shown;
    }
  }

  ChatPollAnswer _answerAt(int index) {
    final question = widget.poll.shownQuestions[index];
    final mine = question.myAnswer;
    return switch (question.type) {
      ChatPollType.single || ChatPollType.multiple => ChatPollAnswer(
        choices: _choices[index] ?? mine?.choices ?? const [],
      ),
      ChatPollType.text => ChatPollAnswer(text: _fields[index].text),
      ChatPollType.number => ChatPollAnswer(
        number: ChatPollAnswer.numberText(_fields[index].text),
      ),
      ChatPollType.date => ChatPollAnswer(date: _dates[index] ?? mine?.date),
      ChatPollType.rating => ChatPollAnswer(
        rating: _ratings[index] ?? mine?.rating,
      ),
    };
  }

  ChatPollAnswer get _pending {
    final parts = [
      for (var i = 0; i < widget.poll.shownQuestions.length; i++) _answerAt(i),
    ];
    return parts.length == 1 ? parts.single : ChatPollAnswer(parts: parts);
  }

  void _pick(int question, int index, bool on) {
    final type = widget.poll.shownQuestions[question].type;
    final current =
        _choices[question] ??
        widget.poll.shownQuestions[question].myAnswer?.choices ??
        const <int>[];
    setState(() {
      _choices[question] = type == ChatPollType.single
          ? [index]
          : ([...current.where((c) => c != index), if (on) index]..sort());
    });
  }

  Future<void> _pickDate(int index) async {
    final current = ChatPollAnswer.parseDate(
      _dates[index] ?? widget.poll.shownQuestions[index].myAnswer?.date ?? '',
    );
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null || !mounted) return;
    setState(() => _dates[index] = ChatPollAnswer.formatDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final id = widget.id;
    final poll = widget.poll;
    final questions = poll.shownQuestions;
    final mine = poll.myAnswer;
    final onAnswer = widget.onAnswer;
    final onClose = widget.onClose;
    final onExport = widget.onExport;
    final canAnswer =
        onAnswer != null &&
        !poll.isClosed &&
        (mine == null || poll.allowChange);
    final pending = _pending;
    final closesAt = poll.closesAt;
    final muted = TextStyle(color: tokens.mutedForeground, fontSize: 12);
    final showResults = poll.resultsVisible;

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
            for (final (index, question) in questions.indexed) ...[
              if (index > 0) Divider(height: 1, color: tokens.border),
              PollQuestionBody(
                id: id,
                questionIndex: index,
                questionCount: questions.length,
                question: question,
                canAnswer: canAnswer,
                showResults: showResults,
                responseCount: poll.responseCount,
                choices:
                    _choices[index] ?? question.myAnswer?.choices ?? const [],
                field: _fields[index],
                date: _dates[index] ?? question.myAnswer?.date,
                rating: _ratings[index] ?? question.myAnswer?.rating,
                onPick: (option, on) => _pick(index, option, on),
                onFieldChanged: () => setState(() {}),
                onPickDate: () => _pickDate(index),
                onRate: (step) => setState(() => _ratings[index] = step),
                maxTextLength: QuarkPollCard.maxTextLength,
              ),
            ],
            if (!showResults)
              Row(
                key: ValueKey('poll_results_hidden_$id'),
                spacing: tokens.spacingXs,
                children: [
                  Icon(
                    QuarkIcons.visibility_off,
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
