import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../layout/quark_choice_menu.dart';

/// The duplicates view's "Keep" choice (#1666): a `QuarkChoiceMenu` offering
/// "Any" and each file format in [formats], for picking which copy of the
/// same picture saved in two formats (a HEIC and its JPEG) to keep.
///
/// The chip reads "Keep: Any" or "Keep: HEIC", and so on, and shows active
/// while a format is chosen. The caller decides what a choice does.
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
  Widget build(BuildContext context) => QuarkChoiceMenu<String?>(
    keyPrefix: 'duplicates_keep_format',
    icon: QuarkIcons.image_outlined,
    label: 'Keep: ${preferred ?? 'Any'}',
    tooltip: 'Keep format',
    options: [
      (id: 'any', label: 'Any', value: null),
      for (final f in formats) (id: f, label: f, value: f),
    ],
    selected: preferred,
    onChanged: onChanged,
    active: preferred != null,
  );
}
