import 'package:material_ui/material_ui.dart';

import '../../theme/quark_tokens.dart';

/// The heading above a group of rows in `QuarkDrawer`: a hairline unless
/// [divider] is off, then [label] in line with the rows' icons (#2046).
///
/// A screen reader announces it as a heading, so the group can be jumped to.
/// It is not a button and has no keys of its own; `QuarkDrawer` gives it
/// `drawer_group_<name>`.
class QuarkDrawerGroupLabel extends StatelessWidget {
  /// Creates the heading for the group named [label].
  const QuarkDrawerGroupLabel({
    required this.label,
    this.divider = true,
    super.key,
  });

  /// The group's name, such as "Manage".
  final String label;

  /// Whether a hairline separates this group from the one above. The first
  /// group sits under the drawer header and needs none.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (divider) Divider(color: tokens.border),
        Padding(
          // A row's icon starts one spacingMd in; so does the heading.
          padding: EdgeInsetsDirectional.fromSTEB(
            tokens.spacingMd,
            tokens.spacingXs,
            tokens.spacingMd,
            tokens.spacingSm,
          ),
          child: Semantics(
            header: true,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tokens.secondaryForeground,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
