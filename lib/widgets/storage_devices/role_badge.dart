import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Names the role a device has been assigned, as a [QuarkTintBadge]. Renders
/// nothing for a role it does not know, `'unassigned'` included.
class RoleBadge extends StatelessWidget {
  const RoleBadge({required this.role, super.key});

  final String role;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final (label, color) = switch (role) {
      'default-storage' => ('Default Storage', tokens.primary),
      'snapshot-backup' => ('Backup drive', tokens.secondaryForeground),
      _ => (null, null),
    };
    if (label == null) return const SizedBox.shrink();
    return QuarkTintBadge(label: label, color: color);
  }
}
