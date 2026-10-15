import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';
import 'quark_document.dart';
import 'quark_document_view/document_block.dart';
import 'quark_document_view/document_truncated_banner.dart';

/// Builds an embedded document image. The caller resolves and loads [image]'s
/// package part; the widget never touches the network or disk.
typedef QuarkDocumentImageBuilder =
    Widget Function(BuildContext context, QuarkDocumentImage image);

/// A lazy read-only rendering of an office document block stream.
///
/// The view renders headings, paragraphs, lists, tables with spans, images,
/// page breaks, and safe omitted-content markers. It lays out only visible
/// top-level blocks with `ListView.builder`. Images come from [imageBuilder],
/// and a tapped link only calls [onLinkTap]; the caller decides what either
/// may reach.
///
/// The view fills its available height. Key prefixes: `document_block_<n>` on
/// each top-level block and `document_link_<n>` on each link in document
/// order. The retry action is `document_view_retry`, and a limit notice is
/// `document_truncated_banner`.
///
/// ```dart
/// QuarkDocumentView(
///   document: controller.document,
///   onLinkTap: openLink,
///   imageBuilder: (context, image) => PartImage(part: image.part!),
/// );
/// ```
class QuarkDocumentView extends StatelessWidget {
  /// Creates a view rendering [document].
  const QuarkDocumentView({
    required this.document,
    this.isLoading = false,
    this.error,
    this.onRetry,
    this.onLinkTap,
    this.imageBuilder,
    super.key,
  });

  /// The widest the document column grows.
  static const double maxContentWidth = 800;

  /// The parsed document.
  final QuarkDocument document;

  /// Whether the document is loading for the first time.
  final bool isLoading;

  /// The caller-composed load error; null when loading succeeded.
  final String? error;

  /// Called when Retry is tapped. Null leaves the button out.
  final VoidCallback? onRetry;

  /// Called with a link target exactly as the document wrote it.
  final ValueChanged<String>? onLinkTap;

  /// Builds each embedded image. Null shows an alt-text placeholder.
  final QuarkDocumentImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final error = this.error;
    final onRetry = this.onRetry;
    final summary = document.summary;
    final style = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      color: tokens.foreground,
      height: 1.5,
    );
    if (isLoading) return const Center(child: QuarkLoader());
    if (error != null) {
      return EmptyStateWidget(
        icon: QuarkIcons.error_outline,
        headline: error,
        action: onRetry == null
            ? null
            : FilledButton(
                key: const ValueKey('document_view_retry'),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
      );
    }
    if (document.isEmpty) {
      return const EmptyStateWidget(
        icon: QuarkIcons.description_outlined,
        headline: 'Empty document',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary?.truncated ?? false)
          DocumentTruncatedBanner(summary: summary!),
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(vertical: tokens.spacingLg),
              itemCount: document.blocks.length,
              itemBuilder: (context, index) => Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  key: ValueKey('document_block_$index'),
                  constraints: const BoxConstraints(maxWidth: maxContentWidth),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: tokens.spacingLg,
                      right: tokens.spacingLg,
                      bottom: tokens.spacingMd,
                    ),
                    child: DocumentBlockView(
                      block: document.blocks[index],
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
