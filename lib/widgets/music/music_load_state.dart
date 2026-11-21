import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/slides/slides_error_view.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What a Music page shows in place of its content: a loader while the
/// first listing is on its way, the error view with a retry when it failed,
/// and [child] otherwise.
///
/// [SlidesErrorView]'s `slides_retry` is the retry button.
class MusicLoadState extends StatelessWidget {
  /// Shows [child] unless [loading] or [error] says otherwise.
  const MusicLoadState({
    required this.loading,
    required this.error,
    required this.action,
    required this.onRetry,
    required this.child,
    super.key,
  });

  /// Whether the first listing is still on its way, with nothing to show.
  final bool loading;

  /// The thrown object from the last refresh, not its message —
  /// [SlidesErrorView] decides what it means.
  final Object? error;

  /// What failed, read after "Couldn't", such as `'load your music'`.
  final String action;

  /// Called by the error view's retry button.
  final VoidCallback onRetry;

  /// The content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: QuarkLoader());
    final error = this.error;
    if (error != null) {
      return SlidesErrorView(error: error, action: action, onRetry: onRetry);
    }
    return child;
  }
}
