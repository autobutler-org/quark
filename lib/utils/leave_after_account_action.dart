import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/account_actions_controller.dart';

/// Runs [action] on [controller], then either reports why it failed or leaves
/// the app for wherever a signed-out user belongs.
///
/// Shared by deleting an account and resetting the Quark, which both end the
/// session they run in. [done] is what the user is told on the way out. The
/// Quark reports whether files survived, so the notice about them is the
/// truth after the fact rather than a second guess at what was asked for. The
/// snack bar is shown before navigating on purpose: the root
/// [ScaffoldMessenger] outlives the calling route, so the message survives the
/// trip to setup or login.
Future<void> leaveAfterAccountAction(
  BuildContext context,
  AccountActionsController controller,
  Future<String?> Function() action,
  String done,
) async {
  final destination = await action();
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  if (destination == null) {
    messenger.showSnackBar(SnackBar(content: Text(controller.error!)));
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        controller.filesRetained
            ? '$done Your files are still on this Quark.'
            : done,
      ),
    ),
  );
  // The token is already gone, so the router's gate would move the user on
  // regardless. Going straight there means they never watch the page fail to
  // load against a Quark they can no longer sign in to.
  context.go(destination);
}
