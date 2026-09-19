import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/ssh_key_item.dart';
import '../../theme/quark_tokens.dart';

/// One allowed key in an `SshAccessPanel`: its comment (or type), its
/// fingerprint, and a remove button.
///
/// Key prefixes: `ssh_key_<fingerprint>` on the row and
/// `ssh_remove_key_<fingerprint>` on its remove button.
class SshKeyRow extends StatelessWidget {
  /// Creates the row for [item].
  const SshKeyRow({required this.item, this.onRemove, super.key});

  /// The key to draw.
  final SshKeyItem item;

  /// Called with [SshKeyItem.fingerprint] when remove is tapped. Null
  /// disables the button.
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onRemove = this.onRemove;
    return ListTile(
      key: ValueKey('ssh_key_${item.fingerprint}'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(QuarkIcons.key_outlined),
      title: Text(
        item.comment.isEmpty ? item.type : item.comment,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        item.fingerprint,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: tokens.mutedForeground),
      ),
      trailing: IconButton(
        key: ValueKey('ssh_remove_key_${item.fingerprint}'),
        tooltip: 'Remove key',
        icon: const Icon(QuarkIcons.delete_outline),
        onPressed: onRemove == null ? null : () => onRemove(item.fingerprint),
      ),
    );
  }
}
