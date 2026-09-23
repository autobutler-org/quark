import 'package:flutter/material.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/spell_check.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The plaintext editor's surface: a spinner while the file loads, whatever
/// went wrong, or the text itself.
class PlaintextEditorBody extends StatelessWidget {
  final bool loading;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  final Object? error;
  final VoidCallback onRetry;
  final TextEditingController controller;

  /// Underline misspellings, for a file people write prose in. Only takes
  /// effect on a platform with a spell checker (iOS and Android).
  final bool spellCheck;

  const PlaintextEditorBody({
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.controller,
    this.spellCheck = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: QuarkLoader());
    }

    final error = this.error;
    if (error != null) {
      if (isQuarkUnreachableError(error)) {
        return QuarkDisconnectedView(
          hostAddress: AppSettings.instance.activeHost,
          onRetry: onRetry,
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              Errors.message(error, 'load the file'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: controller,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        spellCheckConfiguration: spellCheck
            ? proseSpellCheck()
            : const SpellCheckConfiguration.disabled(),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Empty file',
          isCollapsed: true,
        ),
      ),
    );
  }
}
