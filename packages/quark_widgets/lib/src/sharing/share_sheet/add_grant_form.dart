import 'package:flutter/material.dart';

import '../../core/quark_loader.dart';
import '../../models/access_level.dart';
import '../../models/principal_item.dart';
import '../../theme/quark_tokens.dart';
import '../../users/principal_picker.dart';

/// The part of a [ShareSheet] that shares the item with someone else: a
/// [PrincipalPicker], a choice of level, and a share button.
///
/// The picked account or group and the level are [State] because they are
/// the form's own transient input; the outcome leaves through [onAdd]. The
/// owner level is only on offer with [canGrantOwner].
///
/// A part of [ShareSheet], tested through it.
///
/// Key prefixes: `share_add_level_<level>`, `share_add_submit`, and the
/// [PrincipalPicker] keys.
class AddGrantForm extends StatefulWidget {
  /// Creates the form offering [principals].
  const AddGrantForm({
    required this.principals,
    required this.onAdd,
    this.canGrantOwner = false,
    this.busyKeys = const {},
    super.key,
  });

  /// The accounts and groups to pick from.
  final List<PrincipalItem> principals;

  /// Called with the picked account or group and the chosen level.
  final void Function(PrincipalItem principal, AccessLevel level) onAdd;

  /// Whether the owner level is offered.
  final bool canGrantOwner;

  /// Key suffixes of principals with a change in flight. The share button
  /// shows progress while the picked one is among them.
  final Set<String> busyKeys;

  @override
  State<AddGrantForm> createState() => _AddGrantFormState();
}

class _AddGrantFormState extends State<AddGrantForm> {
  PrincipalItem? _picked;
  AccessLevel _level = AccessLevel.read;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final picked = _picked;
    // Owner falls back to view if the caller stops being able to grant it.
    final level = _level == AccessLevel.owner && !widget.canGrantOwner
        ? AccessLevel.read
        : _level;
    final isBusy = picked != null && widget.busyKeys.contains(picked.keySuffix);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Share with',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: tokens.spacingSm),
        PrincipalPicker(
          options: widget.principals,
          selected: picked,
          searchLabel: 'Search accounts and groups',
          onSelected: (principal) => setState(() => _picked = principal),
        ),
        SizedBox(height: tokens.spacingSm),
        Wrap(
          spacing: tokens.spacingSm,
          runSpacing: tokens.spacingSm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final option in AccessLevel.values)
              if (option != AccessLevel.owner || widget.canGrantOwner)
                ChoiceChip(
                  key: ValueKey('share_add_level_${option.name}'),
                  label: Text(option.label),
                  selected: option == level,
                  onSelected: (_) => setState(() => _level = option),
                ),
            FilledButton(
              key: const ValueKey('share_add_submit'),
              onPressed: picked == null || isBusy
                  ? null
                  : () => widget.onAdd(picked, level),
              child: isBusy ? const QuarkLoader(size: 20) : const Text('Share'),
            ),
          ],
        ),
      ],
    );
  }
}
