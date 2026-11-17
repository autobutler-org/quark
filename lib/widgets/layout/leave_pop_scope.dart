import 'package:material_ui/material_ui.dart';

/// Catches a system back on a page that was opened at its own URL, with
/// nothing underneath it to pop to, and calls [onLeave] instead of letting the
/// back close the app. With a page underneath, back pops as usual, unless the
/// page is [dirty]: then [mayLeave] is asked first and the page pops only on
/// a yes.
///
/// A page opened by `context.go` is the usual case: Files, a viewer's Edit and
/// a shared link all open an editor or viewer that way (#2078). [onLeave]
/// usually goes to `AppRoutes.leaveFile`; the page's own back button calls
/// the same thing, and asks [mayLeave] itself.
class LeavePopScope extends StatelessWidget {
  const LeavePopScope({
    super.key,
    required this.onLeave,
    this.dirty = false,
    this.mayLeave,
    required this.child,
  });

  /// Leaves the page when there is nothing to pop back to.
  final VoidCallback onLeave;

  /// Whether the page holds edits a back would lose.
  final bool dirty;

  /// Asked before a back pops a [dirty] page; true lets it go. Without it a
  /// dirty page pops as a clean one does.
  final Future<bool> Function()? mayLeave;

  /// The page.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final ask = dirty ? mayLeave : null;
    return PopScope(
      canPop: canPop && ask == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!canPop) return onLeave();
        if (await ask!() && context.mounted) Navigator.of(context).pop();
      },
      child: child,
    );
  }
}
