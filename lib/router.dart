import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/docs_page.dart';
import 'package:quark/pages/document_editor_page.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/pages/health_page.dart';
import 'package:quark/pages/login_page.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/pages/plaintext_editor_page.dart';
import 'package:quark/pages/recover_page.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/pages/setup_page.dart';
import 'package:quark/pages/sheets_page.dart';
import 'package:quark/pages/spreadsheet_editor_page.dart';
import 'package:quark/pages/storage_devices_page.dart';
import 'package:quark/pages/terms_page.dart';
import 'package:quark/pages/vault_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/utils/file_browser_path_utils.dart';

// Route paths — use these constants everywhere instead of string literals.
class AppRoutes {
  static const files = '/files';

  /// Legacy alias. The file browser lived at /cirrus for the product's whole
  /// life, so external links and bookmarks exist. This redirects to [files].
  ///
  // TODO(pre-v1.0.0, #1601): delete this constant and the two /cirrus GoRoutes
  // that redirect to /files.
  static const legacyCirrus = '/cirrus';

  /// Deep-link pattern for opening a specific file in the correct viewer.
  /// e.g. /view/photos/2024/beach.jpg resolves the type and opens the viewer.
  static const viewFile = '/view';

  /// Deep-link pattern for a specific path inside the file browser.
  /// e.g. /files/photos/2024 navigates directly to photos/2024.
  static const filesDeep = '/files/:path(.*)';

  static const photos = '/photos';
  static const docs = '/docs';
  static const sheets = '/sheets';
  static const devices = '/devices';
  static const health = '/health';
  static const vault = '/vault';
  static const settings = '/settings';
  static const setup = '/setup';
  static const login = '/login';
  static const recover = '/recover';
  static const terms = '/terms';
  static const plaintextEditor = '/edit';

  /// Percent-encode a file path for use in a URL, keeping `/` as the segment
  /// separator.
  ///
  /// go_router always reports the current location percent-encoded, so routes
  /// built here must be encoded too. Raw interpolation produced `/files/my
  /// doc.qdoc` while the live location read `/files/my%20doc.qdoc`, and every
  /// site that string-compares a built route against the live location then
  /// mismatched for any name containing a space (#1604).
  static String encodeFilePath(String path) {
    final clean = path.replaceAll(RegExp(r'^/+'), '');
    if (clean.isEmpty) {
      return clean;
    }
    return clean.split('/').map(Uri.encodeComponent).join('/');
  }

  /// Canonical form of [route] for comparison against the live go_router
  /// location. Both sides go through `Uri.parse`, so a route that differs only
  /// in percent-encoding still compares equal (#1604).
  static String canonicalRoute(String route) {
    try {
      return Uri.parse(route).toString();
    } on FormatException {
      return route;
    }
  }

  /// Build a URL for a specific plaintext file.
  /// e.g. plaintextEditorPath('notes/readme.txt') → '/edit/notes/readme.txt'
  /// Device serial is passed as a query param when non-empty.
  static String plaintextEditorPath(String path, {String? serial}) {
    final clean = encodeFilePath(path);
    final base = '$plaintextEditor/$clean';
    return (serial != null && serial.isNotEmpty)
        ? '$base?serial=${Uri.encodeQueryComponent(serial)}'
        : base;
  }

  /// Build a deep-link URL that opens [path] in the correct viewer.
  /// e.g. viewFile('photos/beach.jpg') → '/view/photos/beach.jpg'
  /// Device serial is passed as a query param when non-empty.
  static String viewFilePath(String path, {String? serial}) {
    final clean = encodeFilePath(path);
    final base = '$viewFile/$clean';
    return (serial != null && serial.isNotEmpty)
        ? '$base?serial=${Uri.encodeQueryComponent(serial)}'
        : base;
  }

  /// Build a deep-link URL for a given files path.
  /// e.g. filesPath('photos/2024') → '/files/photos/2024'
  static String filesPath(String path) {
    final clean = encodeFilePath(path);
    return clean.isEmpty ? files : '$files/$clean';
  }

  /// Build a URL for a specific document file.
  /// e.g. docFile('reports/q1.qdoc') → '/docs/reports/q1.qdoc'
  /// Device serial is passed as a query param when non-empty.
  static String docFile(String path, {String? serial}) {
    final clean = encodeFilePath(path);
    final base = '$docs/$clean';
    return (serial != null && serial.isNotEmpty)
        ? '$base?serial=${Uri.encodeQueryComponent(serial)}'
        : base;
  }

  /// Build a URL for a specific spreadsheet file.
  /// e.g. sheetFile('data/budget.qsheet') → '/sheets/data/budget.qsheet'
  static String sheetFile(String path, {String? serial}) {
    final clean = encodeFilePath(path);
    final base = '$sheets/$clean';
    return (serial != null && serial.isNotEmpty)
        ? '$base?serial=${Uri.encodeQueryComponent(serial)}'
        : base;
  }

  /// The files route for the folder that holds [filePath].
  /// e.g. containingFolder('reports/2024/q1.qdoc') → '/files/reports/2024'
  ///
  /// Where an editor lands when it is closed with nothing underneath it to pop
  /// back to — a deep link, a pasted URL, a link someone shared. Sending those
  /// to [files] instead put the user in the home folder however deep the
  /// document lived (#1749).
  static String containingFolder(String filePath) =>
      filesPath(parentPath(filePath));
}

/// Everything that can invalidate the [authRedirect] gate.
///
/// A state change missing from this list leaves the gate stale until some
/// unrelated navigation happens to re-run it — which is how connecting to a
/// Quark used to show the terms page late (#1623).
final Listenable routerRefreshListenable = Listenable.merge([
  // A 401 clears the session token; redirect to login immediately.
  AppSettings.instance.sessionTokenNotifier,
  // Terms acceptance is per-Quark, so this flips both when the user accepts
  // and when the active host changes to one they haven't accepted for.
  AppSettings.instance.hasAcceptedTerms,
  // Connecting to (or switching) a Quark re-runs the terms/login gate right
  // away instead of on the next unrelated navigation (#1623).
  AppSettings.instance.activeHostNotifier,
]);

final router = GoRouter(
  // The login page is the landing page (#1639). It is the one route that is
  // always reachable, and it owns host management, so a user pointed at a
  // Quark they can't reach can still fix it instead of being stuck.
  initialLocation: AppRoutes.login,
  redirect: authRedirect,
  refreshListenable: routerRefreshListenable,
  routes: [
    GoRoute(
      path: AppRoutes.files,
      builder: (context, state) => const FileBrowserPage(),
      routes: [
        GoRoute(
          // Matches /files/<anything>, including slashes.
          // Always renders FileBrowserPage so go_router owns the page and
          // URL changes (back, go-up, breadcrumb) correctly trigger
          // didUpdateWidget. FileBrowserPage._openPendingFile stats the path
          // and launches the right viewer for files.
          path: ':path(.*)',
          builder: (context, state) {
            // go_router already percent-decodes path parameters, so this is
            // the real path — decoding again threw for names containing '%'
            // and silently mangled a literal '%20' (#1604).
            final filePath = state.pathParameters['path'] ?? '';
            return FileBrowserPage(initialPath: filePath);
          },
        ),
      ],
    ),
    GoRoute(
      // /view/:path redirects to /files/:path for backward compatibility.
      path: '${AppRoutes.viewFile}/:path(.*)',
      redirect: (context, state) {
        final raw = state.pathParameters['path'] ?? '';
        final serial = state.uri.queryParameters['serial'];
        final base = AppRoutes.filesPath(raw);
        return serial != null && serial.isNotEmpty
            ? '$base?serial=${Uri.encodeQueryComponent(serial)}'
            : base;
      },
    ),
    GoRoute(
      // TODO(pre-v1.0.0, #1601): delete this route with the /cirrus alias.
      // /cirrus/:path redirects to /files/:path. The browser lived at /cirrus
      // before the rename, so old links and bookmarks must keep resolving.
      path: '${AppRoutes.legacyCirrus}/:path(.*)',
      redirect: (context, state) {
        final raw = state.pathParameters['path'] ?? '';
        final serial = state.uri.queryParameters['serial'];
        final base = AppRoutes.filesPath(raw);
        return serial != null && serial.isNotEmpty
            ? '$base?serial=${Uri.encodeQueryComponent(serial)}'
            : base;
      },
    ),
    GoRoute(
      // TODO(pre-v1.0.0, #1601): delete this route with the /cirrus alias.
      // Bare /cirrus → /files.
      path: AppRoutes.legacyCirrus,
      redirect: (context, state) => AppRoutes.files,
    ),
    GoRoute(
      path: AppRoutes.photos,
      builder: (context, state) => const PhotosPage(),
    ),
    GoRoute(
      path: AppRoutes.docs,
      builder: (context, state) => const DocsPage(),
    ),
    GoRoute(
      // Matches /docs/<anything including slashes> — opens the doc editor.
      //
      // Top-level, not nested under /docs, and the same for /sheets below —
      // matching how /edit already declares the plaintext editor. A nested
      // editor route makes go_router build the section list underneath every
      // editor, so a deep link the user never navigated to still answers
      // "back" with a page they never visited, and leaving the editor left the
      // folder the document lives in entirely (#1749). Pushing from the list
      // still stacks the list underneath, so that back is unaffected.
      path: '${AppRoutes.docs}/:path(.*)',
      builder: (context, state) {
        final filePath = state.pathParameters['path'] ?? '';
        final serial = state.uri.queryParameters['serial'] ?? '';
        return DocumentEditorPage(filePath: filePath, deviceSerial: serial);
      },
    ),
    GoRoute(
      path: AppRoutes.sheets,
      builder: (context, state) => const SheetsPage(),
    ),
    GoRoute(
      // Matches /sheets/<anything including slashes> — opens the sheet editor.
      path: '${AppRoutes.sheets}/:path(.*)',
      builder: (context, state) {
        final filePath = state.pathParameters['path'] ?? '';
        final serial = state.uri.queryParameters['serial'] ?? '';
        return SpreadsheetEditorPage(filePath: filePath, deviceSerial: serial);
      },
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
      path: AppRoutes.vault,
      builder: (context, state) => const VaultPage(),
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: AppRoutes.setup,
      builder: (context, state) =>
          SetupPage(onSetupComplete: () => context.go(AppRoutes.files)),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) =>
          LoginPage(onLoginSuccess: () => context.go(AppRoutes.files)),
    ),
    GoRoute(
      path: AppRoutes.recover,
      builder: (context, state) => const RecoverPage(),
    ),
    GoRoute(path: AppRoutes.terms, builder: (context, _) => const TermsPage()),
    GoRoute(
      // Matches /edit/<anything including slashes> — opens the plaintext editor.
      path: '${AppRoutes.plaintextEditor}/:path(.*)',
      builder: (context, state) {
        final filePath = state.pathParameters['path'] ?? '';
        final serial = state.uri.queryParameters['serial'] ?? '';
        return PlaintextEditorPage(filePath: filePath, deviceSerial: serial);
      },
    ),
  ],
  errorBuilder: (context, state) =>
      Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
);

/// How the gate asks the Quark whether it has been set up yet.
///
/// A `var` purely so tests can make the probe fail on demand: the
/// unreachable-Quark path below is otherwise only reachable with a real
/// server to take down.
@visibleForTesting
Future<AuthStatus> Function() authStatusProbe = AuthService.checkStatus;

/// Top-level redirect — handles auth gating.
/// The app's auth/terms gate. Exported so tests can drive the real rules
/// without mounting every page in the app.
@visibleForTesting
Future<String?> authRedirect(BuildContext context, GoRouterState state) async {
  final location = state.matchedLocation;

  // The terms page itself, or the redirect below loops.
  if (location == AppRoutes.terms) return null;

  // No Quark configured at all. /setup and /recover are useless too — there is
  // no API base to talk to — so everything lands on login, which is where
  // hosts are added (#1639).
  if (AppSettings.instance.activeHost == null) {
    return location == AppRoutes.login ? null : AppRoutes.login;
  }

  // Terms must be accepted for this Quark before anything else, including the
  // public routes below: with login as the landing page, connecting a Quark
  // from the login page still has to show terms straight away (#1631).
  if (!AppSettings.instance.hasAcceptedTerms.value) return AppRoutes.terms;

  // A stored session is honored on launch instead of asking for credentials
  // again (#1645). This sits above the public-route allowance below, which
  // returns null for /login and would otherwise leave a token-holding user
  // parked on the landing page (#1639).
  //
  // Optimistic: no probe first. A stale token self-heals — checkUnauthorized
  // clears it on any 401, sessionTokenNotifier is in routerRefreshListenable,
  // and the gate re-runs and lands the user back on login.
  if (location == AppRoutes.login &&
      AppSettings.instance.sessionToken != null) {
    return AppRoutes.files;
  }

  // Routes reachable without a session.
  //
  // /login is deliberately not in here (#1827). It used to be, and returning
  // null for it meant the setup-vs-login decision only ever ran for a
  // signed-out user landing on a *protected* route — so picking an unclaimed
  // Quark from the login page left the user on a sign-in form that could only
  // answer "invalid credentials". Falling through to the probe below is what
  // sends them to /setup instead; activeHostNotifier is in
  // routerRefreshListenable, so switching hosts re-runs this.
  const publicRoutes = {AppRoutes.setup, AppRoutes.recover};
  if (publicRoutes.contains(location)) return null;

  // Already authenticated.
  if (AppSettings.instance.sessionToken != null) return null;

  final destination = await destinationForSignedOutUser();
  // /login is public, so "stay put" is a real answer here — returning the
  // location we are already at would be a redirect loop.
  return destination == location ? null : destination;
}

/// Where a user who has accepted terms but holds no session belongs:
/// [AppRoutes.setup] on a Quark nobody has claimed yet, [AppRoutes.login]
/// otherwise.
///
/// An unreachable Quark also resolves to [AppRoutes.login]. This used to
/// resolve to "stay where you are", which stranded a signed-out user on a
/// /files that could only render errors — including the user who had just
/// accepted terms, if the status call happened to fail at that moment (#1624).
/// Login is the screen they need either way, and it surfaces the connection
/// failure when they try to sign in.
///
/// A user already sitting on /login therefore stays there when the probe
/// fails, which is why the sign-in form carries a manual "set up this Quark"
/// link as well — a failed or slow probe must never be the only way to reach
/// /setup (#1827).
Future<String> destinationForSignedOutUser() async {
  try {
    final status = await authStatusProbe();
    return status.setupComplete ? AppRoutes.login : AppRoutes.setup;
  } catch (_) {
    return AppRoutes.login;
  }
}

/// Where to land once terms have just been accepted.
///
/// The terms page navigates here directly rather than bouncing through /files
/// and trusting [authRedirect] to move the user on: that second hop silently
/// did nothing whenever the status call failed (#1624).
Future<String> destinationAfterAcceptingTerms() async {
  final settings = AppSettings.instance;
  // No Quark configured is a login-page state now, not a file-browser one:
  // that is where hosts are added (#1639).
  if (settings.activeHost == null) return AppRoutes.login;
  if (settings.sessionToken != null) return AppRoutes.files;
  return destinationForSignedOutUser();
}
