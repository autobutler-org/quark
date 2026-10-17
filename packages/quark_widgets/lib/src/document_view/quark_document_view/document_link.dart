import 'package:flutter/material.dart';

/// A link in a `QuarkDocumentView` that reports its target to the caller.
class DocumentLink extends StatelessWidget {
  /// Creates a link showing [child].
  const DocumentLink({
    required this.href,
    required this.child,
    this.onTap,
    super.key,
  });

  /// The target exactly as the source document wrote it.
  final String href;

  /// The styled link text.
  final Widget child;

  /// Called with [href] when tapped; null leaves the link inert.
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
