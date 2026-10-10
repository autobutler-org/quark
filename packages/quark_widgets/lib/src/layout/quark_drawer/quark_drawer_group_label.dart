import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';

/// The heading above a group of rows in `QuarkDrawer`: a hairline, then
/// [label] in line with the rows' icons (#2046).
///
/// A screen reader announces it as a heading, so the group can be jumped to.
/// It is not a button and has no keys of its own; `QuarkDrawer` gives it
/// `drawer_group_<name>`.
class QuarkDrawerGroupLabel extends StatelessWidget {
  /// Creates the heading for the group named [label].
  const QuarkDrawerGroupLabel({required this.label, super.key});

  /// The group's name, such as "Manage".
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: tokens.border),
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
