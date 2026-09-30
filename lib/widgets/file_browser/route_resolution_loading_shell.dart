import 'package:flutter/material.dart';
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(QuarkIcons.folder_open, size: 48),
              const SizedBox(height: 16),
              Text(
                isFileRoute ? 'Opening file' : 'Opening folder',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                routeLabel,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const Center(child: QuarkLoader()),
            ],
          ),
        ),
      ),
    );
  }
}
