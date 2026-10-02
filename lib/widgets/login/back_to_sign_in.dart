import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';

/// Sends the system Back gesture on a page reached from sign-in back to the
/// sign-in page (#2067).
///
/// Setup, account recovery and requesting an account are top-level pages
/// opened with `context.go`, so each sits alone on the navigator and Android's
/// Back used to close the app from them. With [enabled] false, Back keeps the
/// user where they are instead — for a step such as a recovery phrase that
/// must not be walked away from.
///
/// ```dart
/// BackToSignIn(child: Scaffold(body: form))
/// ```
class BackToSignIn extends StatelessWidget {
  /// Wraps [child], a page reached from sign-in.
  const BackToSignIn({super.key, this.enabled = true, required this.child});

  /// Whether Back goes to sign-in; false makes it do nothing.
  final bool enabled;

  /// The page.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && enabled) context.go(AppRoutes.login);
      },
      child: child,
    );
  }
}
