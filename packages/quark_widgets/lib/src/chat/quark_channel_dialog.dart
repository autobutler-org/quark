import 'package:flutter/material.dart';

import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';

/// Asks for a channel's name and topic, to create a channel or to change
/// one: a title, two text fields, and a submit button.
///
/// It does not close itself. [onSubmit] receives the trimmed name and topic,
/// and [onCancel] fires on the cancel button; the caller that pushed the
/// dialog pops it, usually once the Quark has accepted the name. While that
/// request is out the caller passes [isSubmitting], and a refusal, such as a
/// name another channel has, comes back in as [error], so the dialog stays
/// open with what was typed.
///
/// The typed text is [State] because it is the form's own transient input,
/// thrown away when the dialog closes.
///
/// Key prefixes: `channel_dialog_name`, `channel_dialog_topic`,
/// `channel_dialog_cancel`, and `channel_dialog_submit`.
///
/// ```dart
/// showDialog<void>(
///   context: context,
///   builder: (ctx) => QuarkChannelDialog(
///     title: 'New channel',
///     submitLabel: 'Create',
///     nameMaxLength: 64,
///     isSubmitting: controller.isSaving,
///     error: saveError,
///     onSubmit: (name, topic) => create(name, topic),
///     onCancel: () => Navigator.of(ctx).pop(),
///   ),
/// );
/// ```
class QuarkChannelDialog extends StatefulWidget {
  /// Creates the dialog titled [title].
  const QuarkChannelDialog({
    required this.title,
    required this.submitLabel,
    required this.onSubmit,
    required this.onCancel,
    this.initialName = '',
    this.initialTopic = '',
    this.nameMaxLength,
    this.topicMaxLength,
    this.isSubmitting = false,
    this.error,
    super.key,
  });

  /// What the dialog is for, such as "New channel" or "Edit #design".
  final String title;

  /// The submit button's label, such as "Create" or "Save".
  final String submitLabel;

  /// Called with the trimmed name and topic when the submit button is tapped
  /// or the keyboard's done key is pressed in the name. Never called with an
  /// empty name; the topic may be empty.
  final void Function(String name, String topic) onSubmit;

  /// Called when the cancel button is tapped.
  final VoidCallback onCancel;

  /// The name the field starts with, for an edit. Empty for a new channel.
  final String initialName;

  /// The topic the field starts with.
  final String initialTopic;

  /// The most characters the name accepts, shown as a counter. Null sets no
  /// limit.
  final int? nameMaxLength;

  /// The most characters the topic accepts. Null sets no limit.
  final int? topicMaxLength;

  /// Whether the channel is being saved. Disables both buttons.
  final bool isSubmitting;

  /// A sentence saying why the last attempt was refused, composed by the
  /// caller. Shown under the fields.
  final String? error;

  @override
  State<QuarkChannelDialog> createState() => _QuarkChannelDialogState();
}

class _QuarkChannelDialogState extends State<QuarkChannelDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _topic = TextEditingController(
    text: widget.initialTopic,
  );

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  bool get _canSubmit => !widget.isSubmitting && _name.text.trim().isNotEmpty;

  void _submit() {
    if (_canSubmit) widget.onSubmit(_name.text.trim(), _topic.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = widget.error;

    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('channel_dialog_name'),
              controller: _name,
              autofocus: true,
              maxLength: widget.nameMaxLength,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixText: '# ',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            SizedBox(height: tokens.spacingSm),
            TextField(
              key: const ValueKey('channel_dialog_topic'),
              controller: _topic,
              maxLength: widget.topicMaxLength,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Topic (optional)',
                border: OutlineInputBorder(),
              ),
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
          key: const ValueKey('channel_dialog_cancel'),
          onPressed: widget.isSubmitting ? null : widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('channel_dialog_submit'),
          onPressed: _canSubmit ? _submit : null,
          child: widget.isSubmitting
              ? const QuarkLoader(size: 20)
              : Text(widget.submitLabel),
        ),
      ],
    );
  }
}
