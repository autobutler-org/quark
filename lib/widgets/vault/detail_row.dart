import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark_icons/quark_icons.dart';

/// One labeled field in a vault entry's details, optionally with a copy button.
class DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copiable;
  final String? copyValue;
  final Widget? trailing;

  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.copiable = false,
    this.copyValue,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: SelectableText(value)),
              if (copiable)
                IconButton(
                  icon: const Icon(QuarkIcons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: copyValue ?? value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$label copied'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ?trailing,
            ],
          ),
        ],
      ),
    );
  }
}
