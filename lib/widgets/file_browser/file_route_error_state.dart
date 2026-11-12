import 'package:material_ui/material_ui.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/files_route_path_utils.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the file browser shows when a `/files/<file>` deep link could not be
/// opened. The three flags mirror the reasons the resolution can fail; none of
/// them is a guess about the file, only what the Quark reported.
class FileRouteErrorState extends StatelessWidget {
  const FileRouteErrorState({
    required this.requestedPath,
    required this.isUnreachable,
    required this.isUnsupported,
    required this.isUnauthorized,
    required this.onRetry,
    required this.onManageHosts,
    required this.onOpenPath,
    required this.onGoHome,
    super.key,
  });

  final String requestedPath;
  final bool isUnreachable;
  final bool isUnsupported;
  final bool isUnauthorized;
  final VoidCallback onRetry;
  final VoidCallback onManageHosts;

  /// Navigates to the folder at the given path — used by "Open containing
  /// folder".
  final ValueChanged<String> onOpenPath;
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    if (isUnreachable) {
      return QuarkDisconnectedView(
        hostAddress: AppSettings.instance.activeHost,
        onRetry: onRetry,
        onManageHosts: onManageHosts,
      );
    }
    final routeLabel = filesRouteDisplayPath(requestedPath);
    final parent = parentPath(requestedPath);

    return EmptyStateWidget(
      icon: isUnsupported
          ? QuarkIcons.description_outlined
          : QuarkIcons.error_outline,
      headline: isUnsupported
          ? 'No supported editor'
          : isUnauthorized
          ? 'File access denied'
          : 'File not found',
      subtext: isUnsupported
          ? 'No supported editor is available for $routeLabel. Retry, open the containing folder, or return to /files.'
          : isUnauthorized
          ? 'You do not have access to $routeLabel. Retry, open the containing folder, or return to /files.'
          : 'The file at $routeLabel is unavailable. Retry, open the containing folder, or return to /files.',
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
          if (parent.isNotEmpty)
            OutlinedButton(
              onPressed: () => onOpenPath(parent),
              child: const Text('Open containing folder'),
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
