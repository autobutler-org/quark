import 'package:flutter/material.dart';

/// Names the role a device has been assigned. Renders nothing for a role it
/// does not know, `'unassigned'` included.
class RoleBadge extends StatelessWidget {
  const RoleBadge({required this.role, super.key});

  final String role;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    switch (role) {
      case 'default-storage':
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade800;
        label = 'Default Storage';
      case 'snapshot-backup':
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade800;
        label = 'Backup drive';
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w500),
      ),
    );
  }
}
