import 'package:material_ui/material_ui.dart';

import '../theme/quark_tokens.dart';

/// The one dropdown: a full-width outlined field whose menu is the shared
/// menu panel.
///
/// The field owns the look: it fills its row, grows with its text so a
/// choice still fits at large text sizes (#2606), takes the theme's outlined
/// edge, and opens on the [QuarkTokens.card] fill at the
/// [QuarkTokens.radiusLg] every other menu uses (#4099). The caller owns the
/// item labels and the words around the field.
///
/// Key prefixes: none of its own. The caller's `key` sits on the field.
///
/// ```dart
/// QuarkDropdownField<int>(
///   key: const ValueKey('settings_refresh_interval'),
///   initialValue: 15,
///   items: const [
///     DropdownMenuItem(value: 0, child: Text('Disabled')),
///     DropdownMenuItem(value: 15, child: Text('15 seconds')),
///   ],
///   onChanged: (v) {
///     if (v != null) setInterval(v);
///   },
/// );
/// ```
class QuarkDropdownField<T> extends StatelessWidget {
  /// Creates a dropdown of [items] showing [initialValue].
  const QuarkDropdownField({
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.labelText,
    super.key,
  });

  /// The choices, each labeled by the caller.
  final List<DropdownMenuItem<T>> items;

  /// The choice shown now.
  final T? initialValue;

  /// Called with the picked value. Null disables the field.
  final ValueChanged<T?>? onChanged;

  /// The floating label, such as "Backup". Null for a field under a heading.
  final String? labelText;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    // Flutter's dropdown announces itself as a button even when disabled, so
    // a screen reader offers a button it cannot press. Say it is disabled.
    return Semantics(
      enabled: onChanged != null,
      child: DropdownButtonFormField<T>(
        initialValue: initialValue,
        isExpanded: true,
        itemHeight: null,
        dropdownColor: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        decoration: InputDecoration(
          labelText: labelText,
          contentPadding: EdgeInsets.symmetric(
            horizontal: tokens.spacingSm + tokens.spacingXs,
            vertical: tokens.spacingSm,
          ),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}
