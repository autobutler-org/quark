import 'package:flutter/material.dart';
import 'package:quark/utils/clipboard_utils.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A block of monospace text the user can select and copy, such as a command to run.
class CodeBlock extends StatelessWidget {
  const CodeBlock({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          CopyButton(
            text: text,
            onCopy: (value) => copyToClipboard(context, value),
            unavailableReason: clipboardUnavailableReason,
          ),
        ],
      ),
    );
  }
}
