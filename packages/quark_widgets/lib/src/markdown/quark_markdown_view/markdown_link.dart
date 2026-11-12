import 'package:material_ui/material_ui.dart';

/// A link inside a `QuarkMarkdownView`'s text: [child], announced as a link,
/// that calls [onTap] with [href] when tapped. It opens nothing itself.
///
/// Key prefixes: none of its own. The view keys each link
/// `markdown_link_<n>`.
///
/// ```dart
/// MarkdownLink(
///   href: 'https://example.com',
///   onTap: openLink,
///   child: const Text('Example'),
/// );
/// ```
class MarkdownLink extends StatelessWidget {
  /// Creates a link to [href] showing [child].
  const MarkdownLink({
    required this.href,
    required this.child,
    this.onTap,
    super.key,
  });

  /// The link's target, exactly as the document wrote it.
  final String href;

  /// The link's styled text.
  final Widget child;

  /// Called with [href] when the link is tapped. Null leaves it inert.
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    if (onTap == null) return child;
    return MergeSemantics(
      child: Semantics(
        link: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(onTap: () => onTap(href), child: child),
        ),
      ),
    );
  }
}
