import 'package:material_ui/material_ui.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the file browser shows when the listing for [currentPath] failed.
class FolderRouteErrorState extends StatelessWidget {
  const FolderRouteErrorState({
    required this.error,
    required this.currentPath,
    required this.onRetry,
    required this.onManageHosts,
    required this.onOpenPath,
    required this.onGoHome,
    super.key,
  });

  final Object error;
  final String currentPath;
  final VoidCallback onRetry;
  final VoidCallback onManageHosts;

  /// Navigates to the folder at the given path — used by "Go to parent".
  final ValueChanged<String> onOpenPath;
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    // Copied to a local so the type test below promotes; a field never does.
    final error = this.error;

    // A Quark the app never reached is not a folder problem, and "Go to
    // parent" cannot fix it — say what is actually wrong instead (#1637).
    if (isQuarkUnreachableError(error)) {
      return QuarkDisconnectedView(
        hostAddress: AppSettings.instance.activeHost,
        onRetry: onRetry,
        onManageHosts: onManageHosts,
      );
    }
    final requestError = error is FilesRequestException ? error : null;
    final isMissingFolder = requestError?.statusCode == 404;
    final isUnauthorized =
        requestError?.statusCode == 401 || requestError?.statusCode == 403;
    final normalizedPath = normalizePath(currentPath);
    final routeLabel = normalizedPath.isEmpty
        ? AppRoutes.files
        : AppRoutes.filesPath(normalizedPath);
    final parent = parentPath(normalizedPath);

    return EmptyStateWidget(
      icon: isUnauthorized
          ? QuarkIcons.lock_outline
          : isMissingFolder
          ? QuarkIcons.folder_off_outlined
          : QuarkIcons.error_outline,
      headline: isUnauthorized
          ? 'Access denied'
          : isMissingFolder
          ? 'Folder not found'
          : 'Unable to open folder',
      subtext: isUnauthorized
          ? 'You do not have access to $routeLabel. Retry, move up a level, or return to /files.'
          : isMissingFolder
          ? 'The folder at $routeLabel is unavailable. Retry, move up a level, or return to /files.'
          : 'Files could not load $routeLabel. Retry, move up a level, or return to /files.',
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
          if (parent.isNotEmpty)
            OutlinedButton(
              onPressed: () => onOpenPath(parent),
              child: const Text('Go to parent'),
            ),
          OutlinedButton(
            onPressed: onGoHome,
            child: const Text('Go to /files'),
          ),
        ],
      ),
    );
  }
}
