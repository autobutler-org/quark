import 'package:material_ui/material_ui.dart';

import '../../core/quark_loader.dart';
import '../../theme/quark_tokens.dart';

/// The row under the last line of a `QuarkCodeViewer` while more of the file
/// is still on the server: a "Load more" button, a loader while the next part
/// is on its way, or [loadMoreError] with the button as "Retry".
///
/// Key prefixes: `code_viewer_load_more` on the button.
///
/// ```dart
/// CodeViewerFooter(
///   isLoadingMore: controller.isLoadingMore,
///   loadMoreError: controller.loadMoreError,
///   onLoadMore: controller.loadMore,
/// );
/// ```
class CodeViewerFooter extends StatelessWidget {
  /// Creates the footer.
  const CodeViewerFooter({
    required this.isLoadingMore,
    required this.loadMoreError,
    required this.onLoadMore,
    super.key,
  });

  /// Whether the next part is being loaded, which shows a loader in place of
  /// the button.
  final bool isLoadingMore;

  /// Why the last load failed, rendered as given; null when it did not.
  final String? loadMoreError;

  /// Called when the button is tapped. Null renders it disabled.
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = loadMoreError;
    return Padding(
      padding: EdgeInsets.all(tokens.spacingMd),
      child: isLoadingMore
          ? const Center(child: QuarkLoader(size: 20))
          : Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: tokens.spacingMd,
              runSpacing: tokens.spacingSm,
              children: [
                if (error != null)
                  Text(error, style: TextStyle(color: tokens.error)),
                OutlinedButton(
                  key: const ValueKey('code_viewer_load_more'),
                  onPressed: onLoadMore,
                  child: Text(error == null ? 'Load more' : 'Retry'),
                ),
              ],
            ),
    );
  }
}
