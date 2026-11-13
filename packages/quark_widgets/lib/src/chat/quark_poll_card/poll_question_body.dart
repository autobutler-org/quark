import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../calendar/calendar_event_editor/editor_picker_button.dart';
import '../../calendar/calendar_labels.dart';
import '../../models/chat_poll_answer.dart';
import '../../models/chat_poll_question_item.dart';
import '../../models/chat_poll_type.dart';
import '../../theme/quark_tokens.dart';
import 'poll_option_tally.dart';

/// One question inside `QuarkPollCard`: its prompt, the input for its type,
/// and the tally while the reader may see results.
///
/// A part of `QuarkPollCard`, tested through it. Keys are the card's, with
/// `_q<index>` after the name when the poll has more than one question.
class PollQuestionBody extends StatelessWidget {
  /// Creates the body of question [questionIndex].
  const PollQuestionBody({
    required this.id,
    required this.questionIndex,
    required this.questionCount,
    required this.question,
    required this.canAnswer,
    required this.showResults,
    required this.responseCount,
    required this.choices,
    required this.field,
    required this.date,
    required this.rating,
    required this.onPick,
    required this.onFieldChanged,
    required this.onPickDate,
    required this.onRate,
    required this.maxTextLength,
    super.key,
  });

  /// The poll message's id, which the keys carry.
  final String id;

  /// Where this question sits in the poll, starting at 0.
  final int questionIndex;

  /// How many questions the poll has. One question keeps the keys as they are.
  final int questionCount;

  /// The question and its tally.
  final ChatPollQuestionItem question;

  /// Whether the reader can change the answer.
  final bool canAnswer;

  /// Whether the tally is drawn.
  final bool showResults;

  /// How many people have answered the poll.
  final int responseCount;

  /// The options currently picked.
  final List<int> choices;

  /// The text or number being written. Unused for the other types.
  final TextEditingController field;

  /// The chosen day, `YYYY-MM-DD`, or null.
  final String? date;

  /// The chosen step, or null.
  final int? rating;

  /// Picks or clears option [index].
  final void Function(int index, bool on) onPick;

  /// Called when [field] changes.
  final VoidCallback onFieldChanged;

  /// Opens the date picker.
  final VoidCallback onPickDate;

  /// Picks rating [step].
  final ValueChanged<int> onRate;

  /// The longest written answer, in characters.
  final int maxTextLength;

  String _key(String name, [int? index]) {
    final q = questionCount == 1 ? '' : '_q$questionIndex';
    final suffix = index == null ? '' : '_$index';
    return 'poll_$name${q}_$id$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final prompt = Text(
      question.prompt,
      key: ValueKey(_key('prompt')),
      style: TextStyle(
        color: tokens.foreground,
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: tokens.spacingSm,
      children: [
        prompt,
        switch (question.type) {
          ChatPollType.single => _choices(tokens, radio: true),
          ChatPollType.multiple => _choices(tokens, radio: false),
          ChatPollType.text => _text(tokens),
          ChatPollType.number => _number(tokens),
          ChatPollType.date => _date(tokens),
          ChatPollType.rating => _rating(tokens),
        },
      ],
    );
  }

  Widget _choices(QuarkTokens tokens, {required bool radio}) {
    Widget? tallyOf(int index) => showResults
        ? PollOptionTally(
            key: ValueKey(_key('tally', index)),
            count: question.countAt(index),
            total: responseCount,
          )
        : null;
    final tiles = [
      for (final (index, option) in question.options.indexed)
        if (radio)
          RadioListTile<int>(
            key: ValueKey(_key('option', index)),
            value: index,
            enabled: canAnswer,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(option),
            subtitle: tallyOf(index),
          )
        else
          CheckboxListTile(
            key: ValueKey(_key('option', index)),
            value: choices.contains(index),
            onChanged: canAnswer ? (on) => onPick(index, on ?? false) : null,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(option),
            subtitle: tallyOf(index),
          ),
    ];
    if (!radio) return Column(children: tiles);
    return RadioGroup<int>(
      groupValue: choices.isEmpty ? null : choices.first,
      onChanged: (index) {
        if (canAnswer && index != null) onPick(index, true);
      },
      child: Column(children: tiles),
    );
  }

  Widget _text(QuarkTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: tokens.spacingSm,
    children: [
      TextField(
        key: ValueKey(_key('text')),
        controller: field,
        enabled: canAnswer,
        maxLength: maxTextLength,
        minLines: 1,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Write your answer',
          isDense: true,
        ),
        onChanged: (_) => onFieldChanged(),
      ),
      if (showResults) ..._listed(tokens, ChatPollType.text),
    ],
  );

  Widget _number(QuarkTokens tokens) {
    final average = showResults ? _average(question.textAnswers) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: tokens.spacingSm,
      children: [
        TextField(
          key: ValueKey(_key('number')),
          controller: field,
          enabled: canAnswer,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: const InputDecoration(
            hintText: 'Enter a number',
            isDense: true,
          ),
          onChanged: (_) => onFieldChanged(),
        ),
        if (average != null)
          Text(
            average,
            key: ValueKey(_key('number_average')),
            style: TextStyle(color: tokens.mutedForeground, fontSize: 12),
          ),
        if (showResults) ..._listed(tokens, ChatPollType.number),
      ],
    );
  }

  Widget _date(QuarkTokens tokens) {
    final parsed = date == null ? null : ChatPollAnswer.parseDate(date!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: tokens.spacingSm,
      children: [
        EditorPickerButton(
          key: ValueKey(_key('date')),
          value: parsed == null ? 'Choose a date' : CalendarLabels.date(parsed),
          semanticLabel: 'Answer date',
          onPressed: canAnswer ? onPickDate : null,
        ),
        if (showResults) ..._listed(tokens, ChatPollType.date),
      ],
    );
  }

  Widget _rating(QuarkTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: tokens.spacingXs,
    children: [
      Wrap(
        spacing: tokens.spacingXs,
        children: [
          for (var step = 1; step <= question.scale; step++)
            IconButton(
              key: ValueKey(_key('rating', step)),
              tooltip: 'Rate $step of ${question.scale}',
              onPressed: canAnswer ? () => onRate(step) : null,
              icon: Icon(
                step <= (rating ?? 0)
                    ? QuarkIcons.star
                    : QuarkIcons.star_border,
                color: step <= (rating ?? 0)
                    ? tokens.primary
                    : tokens.mutedForeground,
              ),
            ),
        ],
      ),
      if (showResults)
        for (var step = 1; step <= question.scale; step++)
          Row(
            children: [
              SizedBox(
                width: 16,
                child: Text(
                  '$step',
                  style: TextStyle(color: tokens.mutedForeground, fontSize: 12),
                ),
              ),
              Expanded(
                child: PollOptionTally(
                  key: ValueKey(_key('rating_tally', step)),
                  count: question.ratingAt(step),
                  total: responseCount,
                ),
              ),
            ],
          ),
    ],
  );

  List<Widget> _listed(QuarkTokens tokens, ChatPollType type) => [
    for (final (index, answer) in question.textAnswers.indexed)
      Text(
        _shown(type, answer),
        key: ValueKey(_key('text_answer', index)),
        style: TextStyle(color: tokens.foreground),
      ),
  ];
}

String _shown(ChatPollType type, String raw) {
  if (type != ChatPollType.date) return raw;
  final date = ChatPollAnswer.parseDate(raw);
  return date == null ? raw : CalendarLabels.date(date);
}

/// "Average 3.5", or "Average 3" when it is whole. Null when [numbers] is
/// empty or one of them is not a number.
String? _average(List<String> numbers) {
  if (numbers.isEmpty) return null;
  var sum = 0.0;
  for (final raw in numbers) {
    final value = num.tryParse(raw);
    if (value == null) return null;
    sum += value;
  }
  final average = sum / numbers.length;
  final shown = average == average.roundToDouble()
      ? average.toInt().toString()
      : average.toStringAsFixed(1);
  return 'Average $shown';
}
