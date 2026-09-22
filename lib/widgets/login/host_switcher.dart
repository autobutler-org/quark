import 'package:flutter/material.dart';
import 'package:quark/widgets/host_manager.dart';
import 'package:quark/widgets/login/active_host_card.dart';

/// The active Quark and, when expanded, the inline list of saved ones to
/// switch between, add, edit or remove.
///
/// Shared by the login and setup pages so both offer the same way off a Quark
/// that is the wrong one. Inline rather than in a dialog or sheet: switching
/// hosts can send the router to another page, and a route sitting above this
/// one would be torn down mid-transition (#1623).
class HostSwitcher extends StatelessWidget {
  /// Whether the host list is expanded.
  final bool managingHosts;

  /// Expands or collapses the host list.
  final VoidCallback onToggleManagingHosts;

  /// Fired after a host is added, edited, removed, or made active.
  final VoidCallback onHostsChanged;

  const HostSwitcher({
    super.key,
    required this.managingHosts,
    required this.onToggleManagingHosts,
    required this.onHostsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ActiveHostCard(
          managingHosts: managingHosts,
          onToggleManagingHosts: onToggleManagingHosts,
        ),
        if (managingHosts) ...[
          const SizedBox(height: 8),
          HostManager(onChanged: onHostsChanged),
        ],
      ],
    );
  }
}
