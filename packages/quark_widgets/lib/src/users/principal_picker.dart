import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/principal_item.dart';
import '../theme/quark_tokens.dart';

/// A searchable list of accounts and groups to pick one from, for adding a
/// member to a group or choosing who to share with.
///
/// The options are listed in the order given, and typing in the search field
/// narrows them to names containing the text, ignoring case. Which option is
/// picked is the caller's: [selected] in, [onSelected] out. The search text
/// is [State] because it is the field's own transient input.
///
/// The options lay out as a column rather than scrolling themselves, so the
/// picker sits in a sheet's or a page's own scroll view.
///
/// Key prefixes: `principal_search` on the search field, and
/// `principal_option_<kind>_<id>` on each option, such as
/// `principal_option_user_3` or `principal_option_group_1`.
///
/// ```dart
/// PrincipalPicker(
///   options: controller.principals,
///   selected: picked,
///   onSelected: (principal) => setState(() => picked = principal),
/// );
/// ```
class PrincipalPicker extends StatefulWidget {
  /// Creates the picker over [options].
  const PrincipalPicker({
    required this.options,
    required this.onSelected,
    this.selected,
    this.searchLabel = 'Search',
    super.key,
  });

  /// The accounts and groups on offer, in the order they are shown.
  final List<PrincipalItem> options;

  /// Called with the option that was tapped.
  final ValueChanged<PrincipalItem> onSelected;

  /// The option currently picked, which is marked. Null marks none.
  final PrincipalItem? selected;

  /// The search field's label.
  final String searchLabel;

  @override
  State<PrincipalPicker> createState() => _PrincipalPickerState();
}

class _PrincipalPickerState extends State<PrincipalPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final query = _search.text.trim().toLowerCase();
    final matches = [
      for (final option in widget.options)
        if (query.isEmpty || option.name.toLowerCase().contains(query)) option,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('principal_search'),
          controller: _search,
          decoration: InputDecoration(
            labelText: widget.searchLabel,
            prefixIcon: const Icon(QuarkIcons.search),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        SizedBox(height: tokens.spacingSm),
        if (matches.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: tokens.spacingMd),
            child: Text(
              widget.options.isEmpty ? 'No one to pick' : 'No matches',
              style: TextStyle(color: tokens.mutedForeground),
            ),
          )
        else
          for (final option in matches)
            ListTile(
              key: ValueKey('principal_option_${option.keySuffix}'),
              contentPadding: EdgeInsets.zero,
              selected: option == widget.selected,
              selectedColor: tokens.primary,
              leading: Icon(
                option.kind == PrincipalKind.user
                    ? QuarkIcons.person_outline
                    : Icons.group_outlined,
              ),
              title: Text(
                option.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: option.isBuiltin
                  ? Text(
                      'Every account',
                      style: TextStyle(color: tokens.mutedForeground),
                    )
                  : null,
              trailing: option == widget.selected
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => widget.onSelected(option),
            ),
      ],
    );
  }
}
