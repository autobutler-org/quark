import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/host_item.dart';
import '../theme/quark_tokens.dart';

/// The Quarks found on the local network, one tappable row each.
///
/// Finding them is the caller's job: it passes what it has found so far, and
/// whether it is still looking. Rows win over every other state, so a Quark
/// found mid-search shows at once. With no rows, the error shows if there is
/// one, then a searching line while [isLoading], then a line saying nothing
/// was found.
///
/// Key prefixes: `discovered_quark_<name>` on each row,
/// `discovered_quark_searching` on the searching line, and
/// `discovered_quark_none` on the nothing-found line.
///
/// ```dart
/// DiscoveredQuarkList(
///   quarks: const [HostItem(name: 'Quark on quark', address: 'https://quark.local')],
///   isLoading: controller.isSearching,
///   onSelect: (quark) => addressController.text = quark.address,
/// );
/// ```
class DiscoveredQuarkList extends StatelessWidget {
  /// Creates the list of [quarks].
  const DiscoveredQuarkList({
    required this.quarks,
    this.isLoading = false,
    this.error,
    this.onSelect,
    super.key,
  });

  /// The Quarks found so far, in the order they are shown.
  final List<HostItem> quarks;

  /// Whether the caller is still looking. With no rows, shows a searching line.
  final bool isLoading;

  /// A sentence saying why the search failed, composed by the caller. Shown
  /// when there are no rows.
  final String? error;

  /// Called with the Quark whose row was tapped. Null leaves the rows inert.
  final ValueChanged<HostItem>? onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    final onSelect = this.onSelect;
    final muted = TextStyle(fontSize: 12, color: tokens.mutedForeground);

    if (quarks.isEmpty) {
      if (error != null) {
        return Text(error, style: TextStyle(fontSize: 12, color: tokens.error));
      }
      if (isLoading) {
        return Row(
          key: const ValueKey('discovered_quark_searching'),
          children: [
            const SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: tokens.spacingSm),
            Flexible(
              child: Text('Looking for Quarks on this network…', style: muted),
            ),
          ],
        );
      }
      return Text(
        key: const ValueKey('discovered_quark_none'),
        'No Quarks found on this network.',
        style: muted,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final quark in quarks)
          ListTile(
            key: ValueKey('discovered_quark_${quark.name}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(QuarkIcons.storage_outlined),
            title: Text(quark.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(quark.address, overflow: TextOverflow.ellipsis),
            onTap: onSelect == null ? null : () => onSelect(quark),
          ),
      ],
    );
  }
}
