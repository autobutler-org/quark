import 'package:autobutler/models/plugin_manifest.dart';
import 'package:autobutler/pages/file_browser_page.dart';
import 'package:autobutler/pages/health_page.dart';
import 'package:autobutler/pages/storage_devices_page.dart';
import 'package:autobutler/pages/login_page.dart';
import 'package:autobutler/pages/photos_page.dart';
import 'package:autobutler/pages/recover_page.dart';
import 'package:autobutler/pages/settings_page.dart';
import 'package:autobutler/pages/plugins_page.dart';
import 'package:autobutler/pages/setup_page.dart';
import 'package:autobutler/widgets/plugin_renderer.dart';
import 'package:autobutler/services/app_settings.dart';
import 'package:autobutler/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Route paths — use these constants everywhere instead of string literals.
class AppRoutes {
  static const cirrus = '/cirrus';

  /// Deep-link pattern for a specific path inside the file browser.
  /// e.g. `/cirrus/photos/2024` navigates directly to `photos/2024`.
  static const cirrusDeep = '/cirrus/:path(.*)';

  static const photos = '/photos';
  static const devices = '/devices';
  static const health = '/health';
  static const settings = '/settings';
  static const plugins = '/plugins';
  static const setup = '/setup';
  static const login = '/login';
  static const recover = '/recover';

  /// Plugin pages are served at /plugins/<id>.
  static String pluginPath(String pluginId) => '/plugins/$pluginId';

  // Note: image/video viewers are push-only overlays (take runtime data),
  // not deep-linkable URL routes.

  /// Build a deep-link URL for a given cirrus path.
  /// e.g. cirrusPath('photos/2024') → '/cirrus/photos/2024'
  static String cirrusPath(String path) {
    final clean = path.replaceAll(RegExp(r'^/+'), '');
    return clean.isEmpty ? cirrus : '/cirrus/$clean';
  }
}

/// Builds plugin routes from the given list of manifests.
/// Native plugins are rendered via [pluginPageRegistry]; unknown IDs fall back
/// to a placeholder page.
List<RouteBase> buildPluginRoutes(List<PluginManifest> plugins) {
  return [
    for (final plugin in plugins)
      if (plugin.contributes.navItem != null)
        GoRoute(
          path: AppRoutes.pluginPath(plugin.id),
          builder: (context, state) {
            return PluginPage(
              name: plugin.name,
              pageNode: plugin.contributes.page,
            );
          },
        ),
  ];
}

GoRouter buildRouter({List<PluginManifest> plugins = const []}) {
  return GoRouter(
    initialLocation: AppRoutes.cirrus,
    redirect: _authRedirect,
    routes: [
      GoRoute(
        path: AppRoutes.cirrus,
        builder: (context, state) => const FileBrowserPage(),
        routes: [
          GoRoute(
            // Matches /cirrus/<anything>, including slashes.
            path: ':path(.*)',
            builder: (context, state) {
              final raw = state.pathParameters['path'] ?? '';
              return FileBrowserPage(initialPath: Uri.decodeComponent(raw));
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.photos,
        builder: (context, state) => const PhotosPage(),
      ),
      GoRoute(
        path: AppRoutes.devices,
        builder: (context, state) => const StorageDevicesPage(),
      ),
      GoRoute(
        path: AppRoutes.health,
        builder: (context, state) => const HealthPage(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.plugins,
        builder: (context, state) => const PluginsPage(),
      ),
      GoRoute(
        path: AppRoutes.setup,
        builder: (context, state) =>
            SetupPage(onSetupComplete: () => context.go(AppRoutes.cirrus)),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) =>
            LoginPage(onLoginSuccess: () => context.go(AppRoutes.cirrus)),
      ),
      GoRoute(
        path: AppRoutes.recover,
        builder: (context, state) => const RecoverPage(),
      ),
      ...buildPluginRoutes(plugins),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
}

// Keep a top-level router for compatibility; plugins are loaded at runtime
// and the router is rebuilt via AutobutlerApp state.
final router = buildRouter();

/// Top-level redirect — handles auth gating.
Future<String?> _authRedirect(BuildContext context, GoRouterState state) async {
  final publicRoutes = {AppRoutes.setup, AppRoutes.login, AppRoutes.recover};

  // Public routes are always accessible.
  if (publicRoutes.contains(state.matchedLocation)) return null;

  // No host configured — let the main app handle the "add host" prompt.
  if (AppSettings.instance.activeHost == null) return null;

  // Already authenticated.
  if (AppSettings.instance.sessionToken != null) return null;

  // Check server-side status.
  try {
    final status = await AuthService.checkStatus();
    if (!status.setupComplete) return AppRoutes.setup;
    return AppRoutes.login;
  } catch (_) {
    // Can't reach butler — allow through; individual pages will surface errors.
    return null;
  }
}
