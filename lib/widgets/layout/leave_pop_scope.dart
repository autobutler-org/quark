import 'package:flutter/material.dart';

/// Catches a system back on a page that was opened at its own URL, with
/// nothing underneath it to pop to, and calls [onLeave] instead of letting the
/// back close the app. With a page underneath, back pops as usual.
///
/// A page opened by `context.go` is the usual case: Files, a viewer's Edit and
/// a shared link all open an editor or viewer that way (#2078). [onLeave]
/// usually goes to `AppRoutes.leaveFile`; the page's own back button calls
/// the same thing.
class LeavePopScope extends StatelessWidget {
  const LeavePopScope({super.key, required this.onLeave, required this.child});

  /// Leaves the page when there is nothing to pop back to.
  final VoidCallback onLeave;

  /// The page.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !canPop) onLeave();
      },
      child: child,
    );
  }
}
