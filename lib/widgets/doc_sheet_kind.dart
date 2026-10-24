import 'package:flutter/widgets.dart';
import 'package:quark/widgets/doc_sheet_tile.dart';
import 'package:quark_icons/quark_icons.dart';

/// Which of the two twin list pages a [DocSheetBody] is on: Docs or Sheets.
/// Each carries the words, icon and keys that tell the two apart, and
/// [other] names the type a search also lists in its own section (#2259).
enum DocSheetKind {
  docs(
    noun: 'doc',
    loadAction: 'load your documents',
    icon: QuarkIcons.description_outlined,
    sectionLabel: 'In Docs',
  ),
  sheets(
    noun: 'sheet',
    loadAction: 'load your sheets',
    icon: QuarkIcons.table_chart_outlined,
    sectionLabel: 'In Sheets',
  );

  const DocSheetKind({
    required this.noun,
    required this.loadAction,
    required this.icon,
    required this.sectionLabel,
  });

  /// The singular noun in the empty state's copy: `doc` or `sheet`.
  final String noun;

  /// What a failed listing could not do, for `Errors.message`.
  final String loadAction;

  /// The type's icon, on the empty state and on its section header.
  final IconData icon;

  /// The header over this type's rows when they show on the other page.
  final String sectionLabel;

  /// The type the other page lists.
  DocSheetKind get other => this == docs ? sheets : docs;

  /// Whether [relPath] is a file of this type.
  bool owns(String relPath) => this == docs
      ? DocSheetTile.isDoc(relPath)
      : DocSheetTile.isSheet(relPath);
}
