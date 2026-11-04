import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/chat_poll_draft.dart';
import '../../models/chat_poll_type.dart';
import '../../theme/quark_tokens.dart';

/// One question inside `QuarkPollEditor`: its prompt, its type, and the
/// options or the rating scale that type asks for.
///
/// A part of `QuarkPollEditor`, tested through it. The first question uses
/// the editor's keys as they are (`poll_editor_prompt`). A later question
/// inserts `_q<index>` after `poll_editor`.
class PollEditorQuestion extends StatelessWidget {
  /// Creates the fields for question [index].
  const PollEditorQuestion({
    required this.index,
    required this.questionCount,
    required this.question,
    required this.prompt,
    required this.options,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  /// Where this question sits, starting at 0.
  final int index;

  /// How many questions the draft has.
  final int questionCount;

  /// The question as it stands.
  final ChatPollQuestionDraft question;

  /// The prompt field.
  final TextEditingController prompt;

  /// One controller per option, in order.
  final List<TextEditingController> options;

  /// Called with this question after a change.
  final ValueChanged<ChatPollQuestionDraft> onChanged;

  /// Removes this question. Null while it is the only one.
  final VoidCallback? onRemove;

  String _key(String name) =>
      index == 0 ? 'poll_editor_$name' : 'poll_editor_q${index}_$name';

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final type = question.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: tokens.spacingSm,
      children: [
        if (questionCount > 1)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Question ${index + 1}',
                  key: ValueKey('poll_editor_question_$index'),
                  style: TextStyle(
                    color: tokens.mutedForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  key: ValueKey('poll_editor_question_remove_$index'),
                  tooltip: 'Remove question ${index + 1}',
                  onPressed: onRemove,
                  icon: const Icon(QuarkIcons.remove_circle_outline),
                ),
            ],
          ),
        TextField(
          key: ValueKey(_key('prompt')),
          controller: prompt,
          autofocus: index == 0,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Question'),
          onChanged: (value) => onChanged(question.copyWith(prompt: value)),
        ),
        Wrap(
          spacing: tokens.spacingSm,
          runSpacing: tokens.spacingXs,
          children: [
            for (final choice in ChatPollType.values)
              ChoiceChip(
                key: ValueKey(_key('type_${choice.name}')),
                label: Text(choice.label),
                selected: type == choice,
                // The controllers hold the latest keystrokes; [question] can
                // still be the value from before them.
                onSelected: (_) => onChanged(
                  question.copyWith(
                    type: choice,
                    prompt: prompt.text,
                    options: [for (final field in options) field.text],
                  ),
                ),
              ),
          ],
        ),
        if (type.hasOptions) ...[
          for (final (optionIndex, controller) in options.indexed)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey(_key('option_$optionIndex')),
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: 'Option ${optionIndex + 1}',
                      isDense: true,
                    ),
                    onChanged: (text) => onChanged(
                      question.copyWith(
                        options: [
                          ...question.options.take(optionIndex),
                          text,
                          ...question.options.skip(optionIndex + 1),
                        ],
                      ),
                    ),
                  ),
                ),
                if (options.length > 2)
                  IconButton(
                    key: ValueKey(_key('option_remove_$optionIndex')),
                    tooltip: 'Remove option ${optionIndex + 1}',
                    onPressed: () => onChanged(
                      question.copyWith(
                        options: [
                          ...question.options.take(optionIndex),
                          ...question.options.skip(optionIndex + 1),
                        ],
                      ),
                    ),
                    icon: const Icon(QuarkIcons.remove_circle_outline),
                  ),
              ],
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: ValueKey(_key('option_add')),
              onPressed: () => onChanged(
                question.copyWith(options: [...question.options, '']),
              ),
              icon: const Icon(QuarkIcons.add_rounded, size: 18),
              label: const Text('Add option'),
            ),
          ),
        ],
        if (type == ChatPollType.rating)
          Row(
            children: [
              const Text('Scale'),
              IconButton(
                key: ValueKey(_key('scale_less')),
                tooltip: 'Fewer steps',
                onPressed: question.scale <= ChatPollType.minRating
                    ? null
                    : () => onChanged(
                        question.copyWith(scale: question.scale - 1),
                      ),
                icon: const Icon(QuarkIcons.remove),
              ),
              Text('${question.scale}', key: ValueKey(_key('scale'))),
              IconButton(
                key: ValueKey(_key('scale_more')),
                tooltip: 'More steps',
                onPressed: question.scale >= ChatPollType.maxRating
                    ? null
                    : () => onChanged(
                        question.copyWith(scale: question.scale + 1),
                      ),
                icon: const Icon(QuarkIcons.add_rounded),
              ),
            ],
          ),
      ],
    );
  }
}
