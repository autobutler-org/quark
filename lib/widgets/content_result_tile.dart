import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/widgets/doc_sheet_tile.dart';

/// One full-text search hit in the docs or sheets list, drawn as the same
/// [DocSheetTile] a filename match gets (#2272).
///
/// The hit's own extension decides its icon and which editor it opens, not the
/// page showing it: a .qdoc hit on the Sheets page still opens the doc editor
/// (#2259).
class ContentResultTile extends StatelessWidget {
  final ContentSearchResult result;

  /// The hit carries only a serial, so the body supplies the device's name.
  final String deviceName;
  final bool showDevice;

  const ContentResultTile({
    required this.result,
    required this.deviceName,
    required this.showDevice,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return DocSheetTile(
      relPath: result.relPath,
      deviceName: deviceName,
      showDevice: showDevice,
      snippet: result.plainSnippet,
      onTap: () => context.push(
        DocSheetTile.isSheet(result.relPath)
            ? AppRoutes.sheetFile(result.relPath, serial: result.deviceSerial)
            : AppRoutes.docFile(result.relPath, serial: result.deviceSerial),
      ),
    );
  }
}
