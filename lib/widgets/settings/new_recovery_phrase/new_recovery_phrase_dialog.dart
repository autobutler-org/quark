import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/settings/change_password/change_password_field.dart';
import 'package:quark/widgets/setup/recovery_phrase_step.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The dialog body for giving a short-phrase account a new recovery phrase
/// (#3183): the current password first, then, once the Quark has taken the
/// new phrase, that phrase shown once with [RecoveryPhraseStep].
///
/// Data in, callbacks out: it neither changes anything nor closes itself.
/// [onSubmit] fires with the password; the caller runs the rotation, feeds
/// [isWorking], [error] and then [phrase] back in, and pops the dialog on
/// [onDone], which the phrase step offers only once it is acknowledged.
///
/// Key prefixes: `new_recovery_phrase_password_field`,
/// `new_recovery_phrase_password_visibility`, `new_recovery_phrase_error`,
/// `new_recovery_phrase_cancel`, and `new_recovery_phrase_submit`.
///
/// ```dart
/// QuarkWidget.showDialog<bool>(
///   context,
///   builder: (ctx) => ListenableBuilder(
///     listenable: controller,
///     builder: (ctx, _) => NewRecoveryPhraseDialog(
///       isWorking: controller.isWorking,
///       error: controller.error,
///       phrase: controller.phrase,
///       onSubmit: controller.rotate,
///       onCancel: () => Navigator.of(ctx).pop(),
///       onDone: () => Navigator.of(ctx).pop(true),
///     ),
///   ),
/// );
/// ```
class NewRecoveryPhraseDialog extends StatefulWidget {
  /// Creates the dialog body.
  const NewRecoveryPhraseDialog({
    required this.onSubmit,
    required this.onCancel,
    required this.onDone,
    this.isWorking = false,
    this.error,
    this.phrase,
    super.key,
  });

  /// Called with the password once one has been typed.
  final ValueChanged<String> onSubmit;

  /// Called when the user backs out before a new phrase was made.
  final VoidCallback onCancel;

  /// Called when the user has acknowledged saving the new phrase.
  final VoidCallback onDone;

  /// Whether the rotation is in flight: the field and buttons are disabled
  /// and the submit button shows a loader.
  final bool isWorking;

  /// Why the last attempt failed, from `Errors`, or null.
  final String? error;

  /// The new phrase, shown once, or null while the password is asked for.
  final String? phrase;

  @override
  State<NewRecoveryPhraseDialog> createState() =>
      _NewRecoveryPhraseDialogState();
}

class _NewRecoveryPhraseDialogState extends State<NewRecoveryPhraseDialog> {
  final _passwordController = TextEditingController();
  bool _acknowledged = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !widget.isWorking && _passwordController.text.isNotEmpty;

  void _submit() {
    if (_canSubmit) widget.onSubmit(_passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final phrase = widget.phrase;
    if (phrase != null) {
      return QuarkWidget.alertDialog(
        scrollable: true,
        content: RecoveryPhraseStep(
          phrase: phrase,
          acknowledged: _acknowledged,
          onAcknowledgedChanged: (value) =>
              setState(() => _acknowledged = value ?? false),
          onContinue: widget.onDone,
        ),
      );
    }
    final error = widget.error;
    return QuarkWidget.alertDialog(
      title: const Text('New recovery phrase'),
      scrollable: true,
      content: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your password to make a new recovery phrase. Your old '
              'phrase stops working once the new one is made.',
            ),
            const SizedBox(height: 16),
            ChangePasswordField(
              keyPrefix: 'new_recovery_phrase_password',
              label: 'Password',
              controller: _passwordController,
              autofillHints: const [AutofillHints.password],
              enabled: !widget.isWorking,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error,
                key: const ValueKey('new_recovery_phrase_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Tooltip(
          message: 'Keep your current recovery phrase',
          child: TextButton(
            key: const ValueKey('new_recovery_phrase_cancel'),
            onPressed: widget.isWorking ? null : widget.onCancel,
            child: const Text('Cancel'),
          ),
        ),
        Tooltip(
          message: 'Make a new recovery phrase',
          child: FilledButton(
            key: const ValueKey('new_recovery_phrase_submit'),
            onPressed: _canSubmit ? _submit : null,
            child: widget.isWorking
                ? const QuarkLoader(size: 20)
                : const Text('Make phrase'),
          ),
        ),
      ],
    );
  }
}
