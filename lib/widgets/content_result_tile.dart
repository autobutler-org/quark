import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark_icons/quark_icons.dart';

/// One full-text search hit in the docs or sheets list.
///
/// The hit's own extension decides its icon and which editor it opens, not the
/// page showing it: a .qdoc hit on the Sheets page still opens the doc editor
/// (#2259).
class ContentResultTile extends StatelessWidget {
  final ContentSearchResult result;

  const ContentResultTile({required this.result, super.key});

  /// Whether [relPath] names a spreadsheet rather than a document.
  static bool isSheet(String relPath) =>
      relPath.toLowerCase().endsWith('.qsheet');

  /// Whether [relPath] names a document.
  static bool isDoc(String relPath) => relPath.toLowerCase().endsWith('.qdoc');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sheet = isSheet(result.relPath);

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          sheet
              ? QuarkIcons.table_chart_outlined
              : QuarkIcons.description_outlined,
          size: 18,
          color: colorScheme.onTertiaryContainer,
        ),
      ),
      title: Text(
        result.filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        result.plainSnippet,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colorScheme.onSurface.withValues(alpha: 0.6),
          fontSize: 12,
        ),
      ),
      onTap: () => context.push(
        sheet
            ? AppRoutes.sheetFile(result.relPath, serial: result.deviceSerial)
            : AppRoutes.docFile(result.relPath, serial: result.deviceSerial),
      ),
    );
  }
}
