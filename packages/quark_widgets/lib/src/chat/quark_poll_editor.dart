import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../calendar/calendar_event_editor/editor_picker_button.dart';
import '../calendar/calendar_labels.dart';
import '../core/quark_loader.dart';
import '../models/chat_poll_draft.dart';
import '../models/chat_poll_type.dart';
import '../theme/quark_tokens.dart';

/// The form for a new chat poll: its one question (prompt, type and, for a
/// choice poll, the options) and its four settings (when it closes, whether
/// an answer can change, whether it is anonymous, and whether results wait
/// until it closes), with Post and Cancel.
///
/// It edits nothing itself. Every change comes back through [onChanged] as a
/// new [ChatPollDraft] and the caller hands the next draft in. The caller
/// validates, too: it passes a null [onSave] until the draft can be posted
/// ([ChatPollDraft.isComplete] is the usual test), which disables Post, and
/// [saveError] is a sentence it composed. The close time opens the platform
/// date and time pickers. Its body scrolls, so give it a bounded height.
///
/// Key prefixes: `poll_editor_prompt`, `poll_editor_type_<type>`,
/// `poll_editor_option_<index>`, `poll_editor_option_remove_<index>`,
/// `poll_editor_option_add`, `poll_editor_closes`, `poll_editor_closes_date`,
/// `poll_editor_closes_time`, `poll_editor_allow_change`,
/// `poll_editor_anonymous`, `poll_editor_results_after_close`,
/// `poll_editor_save`, `poll_editor_cancel` and `poll_editor_close`.
///
/// ```dart
/// QuarkPollEditor(
///   draft: draft.value,
///   onChanged: (next) => draft.value = next,
///   onSave: draft.value.isComplete ? post : null,
///   onCancel: () => Navigator.pop(context),
/// );
/// ```
class QuarkPollEditor extends StatefulWidget {
  /// Creates the form around [draft].
  const QuarkPollEditor({
    required this.draft,
    required this.onChanged,
    required this.onCancel,
    this.onSave,
    this.isSaving = false,
    this.saveError,
    super.key,
  });

  /// The poll as it stands.
  final ChatPollDraft draft;

  /// Called with the draft after every change.
  final ValueChanged<ChatPollDraft> onChanged;

  /// Called by Post. Null disables Post.
  final VoidCallback? onSave;

  /// Called by Cancel and by the close button.
  final VoidCallback onCancel;

  /// Whether a post is in flight: the buttons wait and Post shows a loader.
  final bool isSaving;

  /// The caller's sentence about a failed post, or null.
  final String? saveError;

  /// The label of each poll type's chip.
  static String typeLabel(ChatPollType type) => switch (type) {
    ChatPollType.single => 'One choice',
    ChatPollType.multiple => 'Several choices',
    ChatPollType.text => 'Written answer',
  };

  @override
  State<QuarkPollEditor> createState() => _QuarkPollEditorState();
}

/// The form's text controllers, one for the prompt and one per option, kept
/// in step with the draft the caller hands in.
class _QuarkPollEditorState extends State<QuarkPollEditor> {
  late final TextEditingController _prompt = TextEditingController(
    text: widget.draft.prompt,
  );
  late final List<TextEditingController> _options = [
    for (final option in widget.draft.options)
      TextEditingController(text: option),
  ];

  @override
  void didUpdateWidget(QuarkPollEditor old) {
    super.didUpdateWidget(old);
    // Follow a draft the caller replaced, without moving the cursor on the
    // echo of what was just typed.
    final draft = widget.draft;
    if (_prompt.text != draft.prompt) _prompt.text = draft.prompt;
    while (_options.length > draft.options.length) {
      _options.removeLast().dispose();
    }
    for (final (index, option) in draft.options.indexed) {
      if (index == _options.length) {
        _options.add(TextEditingController(text: option));
      } else if (_options[index].text != option) {
        _options[index].text = option;
      }
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(DateTime current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(now) ? now : current,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    widget.onChanged(
      widget.draft.copyWith(
        closesAt: DateTime(
          picked.year,
          picked.month,
          picked.day,
          current.hour,
          current.minute,
        ),
      ),
    );
  }

  Future<void> _pickTime(DateTime current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null || !mounted) return;
    widget.onChanged(
      widget.draft.copyWith(
        closesAt: DateTime(
          current.year,
          current.month,
          current.day,
          picked.hour,
          picked.minute,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final draft = widget.draft;
    final busy = widget.isSaving;
    final saveError = widget.saveError;
    final closesAt = draft.closesAt;
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    void replaceOptions(List<String> options) =>
        widget.onChanged(draft.copyWith(options: options));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            tokens.spacingLg,
            tokens.spacingSm,
            tokens.spacingSm,
            tokens.spacingXs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'New poll',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: tokens.foreground,
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('poll_editor_close'),
                tooltip: 'Close',
                onPressed: busy ? null : widget.onCancel,
                icon: const Icon(QuarkIcons.close_rounded),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacingLg,
              vertical: tokens.spacingSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: tokens.spacingSm,
              children: [
                TextField(
                  key: const ValueKey('poll_editor_prompt'),
                  controller: _prompt,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Question'),
                  onChanged: (prompt) =>
                      widget.onChanged(draft.copyWith(prompt: prompt)),
                ),
                Wrap(
                  spacing: tokens.spacingSm,
                  runSpacing: tokens.spacingXs,
                  children: [
                    for (final type in ChatPollType.values)
                      ChoiceChip(
                        key: ValueKey('poll_editor_type_${type.name}'),
                        label: Text(QuarkPollEditor.typeLabel(type)),
                        selected: draft.type == type,
                        onSelected: (_) =>
                            widget.onChanged(draft.copyWith(type: type)),
                      ),
                  ],
                ),
                if (draft.type != ChatPollType.text) ...[
                  for (final (index, controller) in _options.indexed)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: ValueKey('poll_editor_option_$index'),
                            controller: controller,
                            decoration: InputDecoration(
                              hintText: 'Option ${index + 1}',
                              isDense: true,
                            ),
                            onChanged: (text) => replaceOptions([
                              ...draft.options.take(index),
                              text,
                              ...draft.options.skip(index + 1),
                            ]),
                          ),
                        ),
                        if (_options.length > 2)
                          IconButton(
                            key: ValueKey('poll_editor_option_remove_$index'),
                            tooltip: 'Remove option ${index + 1}',
                            onPressed: () => replaceOptions([
                              ...draft.options.take(index),
                              ...draft.options.skip(index + 1),
                            ]),
                            icon: const Icon(QuarkIcons.remove_circle_outline),
                          ),
                      ],
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const ValueKey('poll_editor_option_add'),
                      onPressed: () => replaceOptions([...draft.options, '']),
                      icon: const Icon(QuarkIcons.add_rounded, size: 18),
                      label: const Text('Add option'),
                    ),
                  ),
                ],
                SwitchListTile(
                  key: const ValueKey('poll_editor_closes'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Close at a set time'),
                  value: closesAt != null,
                  // On starts a day from now, a time the pickers then change.
                  onChanged: (on) => widget.onChanged(
                    on
                        ? draft.copyWith(
                            closesAt: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                          )
                        : draft.copyWith(clearClosesAt: true),
                  ),
                ),
                if (closesAt != null)
                  Row(
                    spacing: tokens.spacingSm,
                    children: [
                      Expanded(
                        flex: 4,
                        child: EditorPickerButton(
                          key: const ValueKey('poll_editor_closes_date'),
                          value: CalendarLabels.date(closesAt),
                          semanticLabel: 'Close date',
                          onPressed: () => _pickDate(closesAt),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: EditorPickerButton(
                          key: const ValueKey('poll_editor_closes_time'),
                          value: CalendarLabels.time(
                            closesAt,
                            use24Hour: use24Hour,
                          ),
                          semanticLabel: 'Close time',
                          onPressed: () => _pickTime(closesAt),
                        ),
                      ),
                    ],
                  ),
                SwitchListTile(
                  key: const ValueKey('poll_editor_allow_change'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow changing an answer'),
                  value: draft.allowChange,
                  onChanged: (on) =>
                      widget.onChanged(draft.copyWith(allowChange: on)),
                ),
                SwitchListTile(
                  key: const ValueKey('poll_editor_anonymous'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Anonymous'),
                  subtitle: const Text(
                    'Nobody, you included, sees who answered what.',
                  ),
                  value: draft.anonymous,
                  onChanged: (on) =>
                      widget.onChanged(draft.copyWith(anonymous: on)),
                ),
                SwitchListTile(
                  key: const ValueKey('poll_editor_results_after_close'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show results after it closes'),
                  subtitle: const Text('Until then only you see the tally.'),
                  value: draft.resultsAfterClose,
                  onChanged: (on) =>
                      widget.onChanged(draft.copyWith(resultsAfterClose: on)),
                ),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: tokens.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.all(tokens.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: tokens.spacingSm,
                children: [
                  if (saveError != null)
                    Text(
                      saveError,
                      style: TextStyle(fontSize: 13, color: tokens.error),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    spacing: tokens.spacingSm,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('poll_editor_cancel'),
                        onPressed: busy ? null : widget.onCancel,
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        key: const ValueKey('poll_editor_save'),
                        onPressed: busy ? null : widget.onSave,
                        child: busy
                            ? const QuarkLoader(size: 18)
                            : const Text('Post poll'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
