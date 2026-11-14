import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/files_route_path_utils.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Shown while a deep-linked `/files/<path>` is still being resolved, before
/// the backend has said whether [path] is a file or a folder.
class RouteResolutionLoadingShell extends StatelessWidget {
  const RouteResolutionLoadingShell({required this.path, super.key});

  final String path;

  @override
  Widget build(BuildContext context) {
    final routeLabel = filesRouteDisplayPath(path);
    final isFileRoute = isLikelyFilePath(path);

    return EmptyStateWidget(
      icon: QuarkIcons.folder_open,
      headline: isFileRoute ? 'Opening file' : 'Opening folder',
      subtext: routeLabel,
      action: const QuarkLoader(),
    );
  }
}
