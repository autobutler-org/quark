import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../layout/quark_bar_chip.dart';
import '../theme/quark_tokens.dart';

/// The duplicates view's "Keep" choice (#1666): a bar chip that opens a menu
/// of "Any" and each file format in [formats], for picking which copy of the
/// same picture saved in two formats (a HEIC and its JPEG) to keep.
///
/// The chip reads "Keep: Any" or "Keep: HEIC", and so on. The caller decides
/// what a choice does.
///
/// Key prefixes: `duplicates_keep_format` on the chip,
/// `duplicates_keep_format_option_<format>` on each menu row, with `any` for
/// "Any".
///
/// ```dart
/// DuplicateFormatButton(
///   formats: const ['HEIC', 'JPEG'],
///   preferred: controller.preferredFormat,
///   onChanged: controller.setPreferredFormat,
/// )
/// ```
class DuplicateFormatButton extends StatelessWidget {
  /// Creates the chip showing [preferred] as the current choice.
  const DuplicateFormatButton({
    required this.formats,
    required this.preferred,
    required this.onChanged,
    super.key,
  });

  /// The formats offered after "Any", as the caller wants them labeled.
  final List<String> formats;

  /// The chosen format, or null for "Any".
  final String? preferred;

  /// Called with the format the user picks, or null when they pick "Any".
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final options = <({String id, String label, String? value})>[
      (id: 'any', label: 'Any', value: null),
      for (final f in formats) (id: f, label: f, value: f),
    ];
    return MenuAnchor(
      style: MenuStyle(
        minimumSize: const WidgetStatePropertyAll(Size(160, 0)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
        ),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: tokens.spacingSm),
        ),
      ),
      menuChildren: [
        for (final option in options)
          MenuItemButton(
            key: ValueKey('duplicates_keep_format_option_${option.id}'),
            trailingIcon: option.value == preferred
                ? Icon(
                    QuarkIcons.check_rounded,
                    size: 16,
                    color: tokens.primary,
                  )
                : null,
            onPressed: () => onChanged(option.value),
            child: Text(option.label),
          ),
      ],
      builder: (context, controller, _) => QuarkBarChip(
        key: const ValueKey('duplicates_keep_format'),
        icon: QuarkIcons.image_outlined,
        label: 'Keep: ${preferred ?? 'Any'}',
        tooltip: 'Keep format',
        active: preferred != null,
        // The label is the current choice, so a phone keeps it too.
        keepLabel: true,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
