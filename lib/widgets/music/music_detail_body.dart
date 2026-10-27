import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/slides_error_view.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The body of an album or artist page: a loader until the first load,
/// the error view with a retry if it failed, and [child] once there is
/// something to show.
class MusicDetailBody extends StatelessWidget {
  /// Creates the body.
  const MusicDetailBody({
    required this.isLoaded,
    required this.error,
    required this.action,
    required this.onRetry,
    required this.child,
    super.key,
  });

  /// Whether a load has succeeded.
  final bool isLoaded;

  /// Why the last load failed, or null.
  final Object? error;

  /// What was being loaded, as a verb phrase for `Errors.message`.
  final String action;

  /// Loads again from the error view.
  final VoidCallback onRetry;

  /// The loaded page.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    if (isLoaded) return child;
    if (error == null) return const Center(child: QuarkLoader());
    return SlidesErrorView(error: error, action: action, onRetry: onRetry);
  }
}
