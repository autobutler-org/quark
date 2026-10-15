import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';
import 'quark_markdown_document.dart';
import 'quark_markdown_view/markdown_block.dart';

/// Builds the widget shown for a Markdown image, given the `src` and `alt`
/// exactly as the document wrote them. The caller resolves and loads `src`.
typedef QuarkMarkdownImageBuilder =
    Widget Function(BuildContext context, String src, String alt);

/// A read-only rendering of a Markdown file: headings, paragraphs, lists,
/// task lists, quotes, GitHub alerts (`> [!NOTE]` and the rest, as colored
/// callouts), code blocks, rules and tables, with selectable text.
///
/// It shows the [document] it is given and does nothing else. Raw HTML in the
/// source is never interpreted: it appears as the text it was written as. The
/// view never touches the network or the disk: an image is whatever
/// [imageBuilder] returns for its `src`, and a tapped link only calls
/// [onLinkTap] with its `href`. The caller decides what either may reach.
///
/// States: a loader while [isLoading]; [error] with a Retry button; "Empty
/// file" when the document has no content; otherwise the rendered text, in a
/// centered column that stops widening on a large screen.
///
/// The view fills the space it is given, so give it a bounded height: an
/// `Expanded`, a page body, a `SizedBox`.
///
/// Key prefixes: `markdown_view_retry`, `markdown_view_status`, and
/// `markdown_link_<n>` on each link, `markdown_image_<n>` on each image,
/// `markdown_task_<n>` on each task list glyph and `markdown_alert_<n>` on
/// each alert, where `<n>` is the 0-based position among links, images, tasks
/// or alerts in document order.
///
/// ```dart
/// QuarkMarkdownView(
///   document: controller.document,
///   isLoading: controller.isLoading,
///   error: controller.error,
///   onRetry: controller.load,
///   onLinkTap: openLink,
///   imageBuilder: (context, src, alt) => FileImage(path: resolve(src)),
/// );
/// ```
class QuarkMarkdownView extends StatelessWidget {
  /// Creates a view rendering [document].
  const QuarkMarkdownView({
    required this.document,
    this.isLoading = false,
    this.error,
    this.onRetry,
    this.onLinkTap,
    this.imageBuilder,
    this.statusLabel,
    super.key,
  });

  /// The widest the text column grows, in logical pixels. Past it the column
  /// is centered.
  static const double maxContentWidth = 760;

  /// The parsed file. `QuarkMarkdownDocument.parse` makes one from source.
  final QuarkMarkdownDocument document;

  /// Whether the file is loading for the first time, which shows a loader in
  /// place of the content.
  final bool isLoading;

  /// Why the file could not be loaded, rendered as given in place of the
  /// content; null when it loaded. The caller composes the sentence.
  final String? error;

  /// Called when Retry is tapped under [error]. Null leaves the button out.
  final VoidCallback? onRetry;

  /// Called with a link's `href`, exactly as the document wrote it, when the
  /// link is tapped. Null renders links styled but inert.
  final ValueChanged<String>? onLinkTap;

  /// Builds each image from its raw `src` and `alt`. Null shows a placeholder
  /// carrying the alt text. The view never loads an image itself.
  final QuarkMarkdownImageBuilder? imageBuilder;

  /// A one-line notice above the content, such as "Showing the first 1 MB of
  /// 5 MB"; null shows nothing.
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quark = QuarkTokens.of(context);
    final error = this.error;
    final onRetry = this.onRetry;
    final statusLabel = this.statusLabel;
    final blocks = document.blocks;
    final style = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      color: quark.foreground,
      height: 1.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (statusLabel != null)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: quark.spacingLg,
              vertical: quark.spacingSm,
            ),
            child: Text(
              statusLabel,
              key: const ValueKey('markdown_view_status'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: quark.mutedForeground,
              ),
            ),
          ),
        Expanded(
          child: isLoading
              ? const Center(child: QuarkLoader())
              : error != null
              ? EmptyStateWidget(
                  icon: QuarkIcons.error_outline,
                  headline: error,
                  action: onRetry == null
                      ? null
                      : FilledButton(
                          key: const ValueKey('markdown_view_retry'),
                          onPressed: onRetry,
                          child: const Text('Retry'),
                        ),
                )
              : document.isEmpty
              ? const EmptyStateWidget(
                  icon: QuarkIcons.description_outlined,
                  headline: 'Empty file',
                )
              : SelectionArea(
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(vertical: quark.spacingLg),
                    itemCount: blocks.length,
                    itemBuilder: (context, index) => Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: maxContentWidth,
                        ),
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: quark.spacingLg,
                            right: quark.spacingLg,
                            bottom: quark.spacingMd,
                          ),
                          child: MarkdownBlock(
                            node: blocks[index],
                            style: style,
                            onLinkTap: onLinkTap,
                            imageBuilder: imageBuilder,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
