import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/chat_controller.dart';
import 'package:quark/models/calendar_view.dart';
import 'package:quark/models/feature_flag.dart';
import 'package:quark/models/trash_item.dart';
import 'package:quark/pages/account_and_data_page.dart';
import 'package:quark/pages/calendar_page.dart';
import 'package:quark/pages/chat_page.dart';
import 'package:quark/pages/docs_page.dart';
import 'package:quark/pages/document_editor_page.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/pages/file_viewer_page.dart';
import 'package:quark/pages/login_page.dart';
import 'package:quark/pages/photo_duplicates_page.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/pages/plaintext_editor_page.dart';
import 'package:quark/pages/recover_page.dart';
import 'package:quark/pages/request_account_page.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/pages/setup_page.dart';
import 'package:quark/pages/sheets_page.dart';
import 'package:quark/pages/spreadsheet_editor_page.dart';
import 'package:quark/pages/system_page.dart';
import 'package:quark/pages/terms_page.dart';
import 'package:quark/pages/trash_page.dart';
import 'package:quark/pages/users_page.dart';
import 'package:quark/pages/vault_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/feature_flags_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/utils/files_route_path_utils.dart';
import 'package:quark_widgets/quark_widgets.dart' show CalendarDates;

// Route paths — use these constants everywhere instead of string literals.
class AppRoutes {
  static const files = '/files';

  /// Legacy alias. The file browser lived at /cirrus for the product's whole
  /// life, so external links and bookmarks exist. This redirects to [files].
  ///
  // TODO(pre-v1.0.0, #1601): delete this constant and the two /cirrus GoRoutes
  // that redirect to /files.
  static const legacyCirrus = '/cirrus';

  /// A file's own viewer, for every kind without an editor of its own.
  /// e.g. /view/photos/2024/beach.jpg opens the photo viewer (#2328).
  static const viewFile = '/view';

  /// Deep-link pattern for a specific path inside the file browser.
  /// e.g. /files/photos/2024 navigates directly to photos/2024.
  static const filesDeep = '/files/:path(.*)';

  static const photos = '/photos';

  /// Photos that duplicate each other, a drill-down from Photos (#1666).
  static const photoDuplicates = '/photos/duplicates';

  /// The query parameter naming the album the Photos page shows.
  static const photosAlbumParam = 'album';

  /// The household calendar (#1144). Its views have their own URLs, see
  /// [calendarView]; this bare path redirects to the default one, Week.
  static const calendar = '/calendar';

  /// The query parameter naming the date a calendar view shows,
  /// `yyyy-mm-dd`. Without it a view shows today.
  static const calendarDateParam = 'date';

  /// The query parameter that narrows the calendar to the signed-in person's
  /// events, `mine=true` (#2544).
  static const calendarMineParam = 'mine';

  /// The query parameter that narrows the calendar to one person's events,
  /// by username (#2544). A separate name from [calendarMineParam], so an
  /// account called "me" is not mistaken for the signed-in one.
  static const calendarPersonParam = 'person';

  /// One calendar view around [date], e.g. calendarView(CalendarView.day,
  /// date: DateTime(2026, 9, 29)) → '/calendar/day?date=2026-09-29', narrowed
  /// to the signed-in person with [mine] or to [person].
  static String calendarView(
    CalendarView view, {
    DateTime? date,
    bool mine = false,
    String? person,
  }) {
    final query = {
      if (date != null) calendarDateParam: CalendarDates.key(date),
      if (mine) calendarMineParam: 'true',
      if (!mine && person != null) calendarPersonParam: person,
    };
    return Uri(
      path: '$calendar/${view.slug}',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  static const trash = '/trash';

  /// The chat beta (#2421). This bare path redirects to the default channel,
  /// [chatChannel] of `general`.
  static const chat = '/chat';

  /// One chat channel by id, e.g. chatChannel('12') → '/chat/12'. `general`
  /// names the default channel; an id the account can't open falls back to
  /// it rather than to an error page.
  static String chatChannel(String channelId) =>
      '$chat/${Uri.encodeComponent(channelId)}';
  static const docs = '/docs';
  static const sheets = '/sheets';
  static const vault = '/vault';

  /// The System page (#2351): the Quark's health, its drives and its jobs,
  /// one tab each. Its tabs have their own URLs, see [systemTab]; this bare
  /// path redirects to the first one.
  static const system = '/system';

  /// One tab of the System page, e.g. systemTab(SystemTab.jobs) →
  /// '/system/jobs'.
  static String systemTab(SystemTab tab) => '$system/${tab.slug}';

  /// Legacy alias. Health was its own page before the System page took it
  /// in as a tab (#2351), so links and bookmarks exist. This redirects to
  /// its tab with the query kept.
  ///
  // TODO(pre-v1.0.0, #1601): delete this constant and its redirect GoRoute.
  static const health = '/health';

  /// Legacy alias for the System page's Storage tab, the drives. See
  /// [health].
  ///
  // TODO(pre-v1.0.0, #1601): delete this constant and its redirect GoRoute.
  static const devices = '/devices';

  /// Legacy alias for the System page's Jobs tab. See [health].
  ///
  // TODO(pre-v1.0.0, #1601): delete this constant and its redirect GoRoute.
  static const jobs = '/jobs';

  /// The admin-only Users page (#1662). Its tabs have their own URLs, see
  /// [usersTab]; this bare path redirects to the first one.
  static const users = '/users';

  /// One tab of the Users page, e.g. usersTab(UsersTab.groups) →
  /// '/users/groups'.
  static String usersTab(UsersTab tab) => '$users/${tab.slug}';

  /// The Settings page. Its tabs have their own URLs, see [settingsTab];
  /// this bare path redirects to the first one (#2350).
  static const settings = '/settings';

  /// Delete account and, for admins, Reset this Quark (#2346). A drill-down
  /// from Settings' Account tab, reached with `context.push`.
  static const accountAndData = '/settings/account-and-data';

  /// One tab of the Settings page, e.g. settingsTab(SettingsTab.general) →
  /// '/settings/general', where the backend hosts are managed.
  static String settingsTab(SettingsTab tab) => '$settings/${tab.slug}';
  static const setup = '/setup';
  static const login = '/login';

  /// The query parameter on [login] carrying the location a signed-out
  /// visitor asked for, so signing in finishes the trip (#2500).
  static const loginFromParam = 'from';

  /// [login] remembering [from], the location a signed-out visitor asked
  /// for. Files is where signing in lands anyway, so it isn't remembered.
  static String loginFrom(String from) => from == files
      ? login
      : Uri(path: login, queryParameters: {loginFromParam: from}).toString();
  static const recover = '/recover';

  /// Alias for [recover]: the address people guess for password recovery
  /// (#2063). Redirects there with the query kept.
  static const forgotPassword = '/forgot-password';

  /// Asking this Quark for an account (#1908). Reachable without a session.
  static const requestAccount = '/request-account';
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

  /// The Photos page showing the album [link] names (see `albumLink`), or All
  /// photos for null.
  /// e.g. photosAlbum('Summer Trip/Japan') → '/photos?album=Summer%20Trip/Japan'
  ///
  /// Everything but `/` is percent-encoded, so `&`, `#`, `+` and `%` in a name
  /// survive; `/` is legal in a query and stays readable in the address bar.
  static String photosAlbum(String? link) => link == null || link.isEmpty
      ? photos
      : '$photos?$photosAlbumParam='
            '${Uri.encodeComponent(link).replaceAll('%2F', '/')}';

  /// Build a deep-link URL for a given files path.
  /// e.g. filesPath('photos/2024') → '/files/photos/2024'
  static String filesPath(String path) {
    final clean = encodeFilePath(path);
    return clean.isEmpty ? files : '$files/$clean';
  }

  /// Build the URL of a folder in the trash: `/trash/<trashName>/<path>`,
  /// with the device serial as a query param when non-empty, the way the
  /// editor routes carry it. Null is the trash root.
  /// e.g. trashFolder((serial: '', trashName: 'x_album', path: '2024'))
  ///   → '/trash/x_album/2024'
  static String trashFolder(TrashLocation? location) {
    if (location == null) return trash;
    final rest = location.path.isEmpty
        ? location.trashName
        : '${location.trashName}/${location.path}';
    final base = '$trash/${encodeFilePath(rest)}';
    return location.serial.isNotEmpty
        ? '$base?serial=${Uri.encodeQueryComponent(location.serial)}'
        : base;
  }

  /// Reads a [trashFolder] URL back: [rest] is everything after `/trash/`,
  /// already decoded by go_router. Null for an empty [rest], the root.
  static TrashLocation? parseTrashFolder(String rest, String serial) {
    final segments = rest.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    return (
      serial: serial,
      trashName: segments.first,
      path: segments.skip(1).join('/'),
    );
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
  ///
  /// [serial] names the device the file is on, carried as a query param when
  /// non-empty the way the editor routes carry it.
  static String containingFolder(String filePath, {String serial = ''}) =>
      _withSerial(filesPath(parentPath(filePath)), serial);
}

/// A tab of a page whose tabs have their own URLs, `/<page>/<slug>`. Each such
/// page declares an enum of its tabs, in the order they show, implementing
/// this; see [tabbedRoutes].
abstract interface class RouteTab {
  /// The tab's URL segment: lowercase, stable, never shown to the user.
  String get slug;
}

/// The Users page's tabs (#2349).
enum UsersTab implements RouteTab {
  accounts('accounts'),
  groups('groups');

  const UsersTab(this.slug);

  @override
  final String slug;
}

/// The System page's tabs (#2351). Health is the overview, so it comes first.
enum SystemTab implements RouteTab {
  health('health'),
  storage('storage'),
  jobs('jobs');

  const SystemTab(this.slug);

  @override
  final String slug;
}

/// The Settings page's tabs (#2350). General comes first: it holds the
/// backend hosts every "manage hosts" link in the app points at.
enum SettingsTab implements RouteTab {
  general('general'),
  account('account'),
  network('network'),
  updates('updates'),
  about('about'),

  /// Admin-only, and hidden while the Quark has no betas (#2542). Last, so
  /// hiding it leaves every other tab's index alone.
  features('features');

  const SettingsTab(this.slug);

  @override
  final String slug;
}

/// The routes of a page at [path] whose [tabs] have their own URLs (#2349):
/// `<path>/<slug>` shows the page on that tab, and bare [path] or an unknown
/// slug redirects to the first tab with the query kept, since a stale link is
/// not a broken app.
///
/// [builder] gets the tab to show and `onTabSelected`, which the page wires to
/// its `QuarkTabView`: it moves with `context.go`, never `push`, so the address
/// bar follows (see AGENTS.md, Navigation and routing).
///
/// Every tab is the one `<path>/:tab` route, and go_router keys a page by its
/// route pattern rather than its location, so switching tabs hands the new
/// tab to the page already on screen: its `State` survives and nothing is
/// loaded again. Keep the tabs in that one route for this to hold.
///
/// [keepQuery] carries the query across a tab switch, for a page whose query
/// is shared by every tab (the date the Calendar's views show).
List<GoRoute> tabbedRoutes<T extends RouteTab>({
  required String path,
  required List<T> tabs,
  required Widget Function(T tab, ValueChanged<T> onTabSelected) builder,
  bool keepQuery = false,
}) {
  String firstTab(GoRouterState state) =>
      state.uri.replace(path: '$path/${tabs.first.slug}').toString();
  return [
    GoRoute(path: path, redirect: (_, state) => firstTab(state)),
    GoRoute(
      path: '$path/:tab',
      redirect: (_, state) {
        final slug = state.pathParameters['tab'];
        return tabs.any((tab) => tab.slug == slug) ? null : firstTab(state);
      },
      builder: (context, state) => builder(
        tabs.firstWhere((tab) => tab.slug == state.pathParameters['tab']),
        (tab) => context.go(
          keepQuery
              ? state.uri.replace(path: '$path/${tab.slug}').toString()
              : '$path/${tab.slug}',
        ),
      ),
    ),
  ];
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
  // An admin demoted while on an admin-only page is moved off it: the flag
  // changing re-runs the gate, which asks the Quark again (#1928).
  AppSettings.instance.isAdmin,
  // A beta turned off moves anyone on its page to Files (#2421, #2542).
  AppSettings.instance.featureFlags,
]);

/// Every route in the app. It opens on the login page, and [authRedirect] sends a visitor who is signed out, or
/// has not accepted the terms, to the page that fixes it.
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
      // Matches /view/<anything including slashes>: the file's own viewer, so
      // a reload or a shared link reopens it and browser back closes it
      // (#2328). Kinds with an editor, folders and archives go where they
      // open instead.
      path: '${AppRoutes.viewFile}/:path(.*)',
      redirect: (context, state) => viewFileRedirect(
        state.pathParameters['path'] ?? '',
        state.uri.queryParameters['serial'],
      ),
      builder: (context, state) => FileViewerPage(
        filePath: state.pathParameters['path'] ?? '',
        serial: state.uri.queryParameters['serial'] ?? '',
      ),
    ),
    GoRoute(
      // TODO(pre-v1.0.0, #1601): delete this route with the /cirrus alias.
      // /cirrus/:path redirects to /files/:path. The browser lived at /cirrus
      // before the rename, so old links and bookmarks must keep resolving.
      path: '${AppRoutes.legacyCirrus}/:path(.*)',
      redirect: (context, state) => _withSerial(
        AppRoutes.filesPath(state.pathParameters['path'] ?? ''),
        state.uri.queryParameters['serial'],
      ),
    ),
    GoRoute(
      // TODO(pre-v1.0.0, #1601): delete this route with the /cirrus alias.
      // Bare /cirrus → /files.
      path: AppRoutes.legacyCirrus,
      redirect: (context, state) => AppRoutes.files,
    ),
    GoRoute(
      path: AppRoutes.photos,
      // An album opens in place, named by the query so reload and a shared
      // link land on it. The page resolves the value once albums load
      // (#1916).
      builder: (context, state) => PhotosPage(
        album: state.uri.queryParameters[AppRoutes.photosAlbumParam],
      ),
      routes: [
        GoRoute(
          path: 'duplicates',
          builder: (context, state) => const PhotoDuplicatesPage(),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.trash,
      builder: (context, state) => const TrashPage(),
      routes: [
        GoRoute(
          // Matches /trash/<trashName>/<path inside it>, a folder being
          // browsed in the trash. Nested like /files/:path so opening a
          // folder, going up and the browser back button all move through
          // go_router, and a deep link lands on the folder.
          path: ':path(.*)',
          builder: (context, state) => TrashPage(
            location: AppRoutes.parseTrashFolder(
              state.pathParameters['path'] ?? '',
              state.uri.queryParameters['serial'] ?? '',
            ),
          ),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.chat,
      redirect: (_, state) => state.uri
          .replace(
            path: AppRoutes.chatChannel(ChatController.defaultChannelSlug),
          )
          .toString(),
    ),
    GoRoute(
      // One route for every channel, so switching channels hands the new id
      // to the page already on screen rather than building it again.
      path: '${AppRoutes.chat}/:channelId',
      builder: (context, state) =>
          ChatPage(channelId: state.pathParameters['channelId']!),
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
        return DocumentEditorPage(
          filePath: filePath,
          deviceSerial: serial,
          // `extra: true` from a create flow opens the new doc editable (#1568).
          startInEditMode: state.extra == true,
        );
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
    ...tabbedRoutes(
      path: AppRoutes.calendar,
      tabs: CalendarView.values,
      keepQuery: true,
      builder: (view, onViewSelected) =>
          CalendarPage(view: view, onViewSelected: onViewSelected),
    ),
    GoRoute(
      path: AppRoutes.vault,
      builder: (context, state) => const VaultPage(),
    ),
    ...tabbedRoutes(
      path: AppRoutes.system,
      tabs: SystemTab.values,
      builder: (tab, onTabSelected) =>
          SystemPage(tab: tab, onTabSelected: onTabSelected),
    ),
    // TODO(pre-v1.0.0, #1601): delete these three with their constants.
    // Health, Devices and Jobs were pages of their own before the System
    // page (#2351); old links land on the matching tab with the query kept.
    for (final (legacy, tab) in [
      (AppRoutes.health, SystemTab.health),
      (AppRoutes.devices, SystemTab.storage),
      (AppRoutes.jobs, SystemTab.jobs),
    ])
      GoRoute(
        path: legacy,
        redirect: (_, state) =>
            state.uri.replace(path: AppRoutes.systemTab(tab)).toString(),
      ),
    ...tabbedRoutes(
      path: AppRoutes.users,
      tabs: UsersTab.values,
      builder: (tab, onTabSelected) =>
          UsersPage(tab: tab, onTabSelected: onTabSelected),
    ),
    // Before the Settings tabs: go_router takes the first match, and
    // `/settings/:tab` would redirect this unknown slug to General.
    GoRoute(
      path: AppRoutes.accountAndData,
      builder: (context, state) => const AccountAndDataPage(),
    ),
    ...tabbedRoutes(
      path: AppRoutes.settings,
      tabs: SettingsTab.values,
      builder: (tab, onTabSelected) =>
          SettingsPage(tab: tab, onTabSelected: onTabSelected),
    ),
    GoRoute(
      path: AppRoutes.setup,
      builder: (context, state) => SetupPage(
        onSetupComplete: () {
          // Finishing the wizard is what earns the welcome card (#2022). The
          // flag is set before the await inside, so Files sees it at once.
          AppSettings.instance.welcomeNewOwner();
          context.go(AppRoutes.files);
        },
      ),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) {
        final params = state.uri.queryParameters;
        return LoginPage(
          onLoginSuccess: () => context.go(
            destinationAfterSignIn(params[AppRoutes.loginFromParam]),
          ),
          initialUsername: params['username'],
          // A password reset lands here and used to say nothing at all
          // (#2029). The query carries it rather than `extra` so the news
          // survives the reload a browser may do on the way.
          notice: params['reset'] == '1'
              ? 'Password updated. Sign in with your new password.'
              : null,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.recover,
      builder: (context, state) =>
          RecoverPage(initialUsername: state.uri.queryParameters['username']),
    ),
    GoRoute(
      path: AppRoutes.forgotPassword,
      redirect: (context, state) =>
          state.uri.replace(path: AppRoutes.recover).toString(),
    ),
    GoRoute(
      path: AppRoutes.requestAccount,
      builder: (context, state) => const RequestAccountPage(),
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

/// Where `/view/[path]` belongs instead, or null when [FileViewerPage] shows
/// it. Docs, sheets and text have editors at their own URLs; a folder or an
/// archive is browsed in Files. [serial] rides along to whichever it is.
String? viewFileRedirect(String path, String? serial) {
  final folder = AppRoutes.filesPath(path);
  if (!isLikelyFilePath(path)) return _withSerial(folder, serial);
  return switch (fileKindForName(path)) {
    FileKind.qdoc => AppRoutes.docFile(path, serial: serial),
    FileKind.qsheet => AppRoutes.sheetFile(path, serial: serial),
    FileKind.text ||
    FileKind.code => AppRoutes.plaintextEditorPath(path, serial: serial),
    FileKind.archive => _withSerial(folder, serial),
    _ => null,
  };
}

String _withSerial(String base, String? serial) =>
    serial != null && serial.isNotEmpty
    ? '$base?serial=${Uri.encodeQueryComponent(serial)}'
    : base;

/// How the app asks the Quark whether it has been set up yet.
///
/// Used by the gate below and by the login page, which offers its setup link
/// only where it leads somewhere (#2030). A `var` so tests can make the probe
/// fail on demand: the unreachable-Quark paths are otherwise only reachable
/// with a real server to take down.
Future<AuthStatus> Function() authStatusProbe = AuthService.checkStatus;

/// Pages only an admin can use, with everything under them, such as a tab's
/// URL. [authRedirect] sends anyone else to [AppRoutes.files]; the Quark
/// refuses their requests either way.
const adminRoutes = {
  AppRoutes.vault,
  AppRoutes.users,
  '${AppRoutes.settings}/features',
};

/// Whether [location] is one of [routes] or a path under one: `/users/groups`
/// is under `/users`, `/users-old` is not. An exact match let a page's tab URLs
/// past the gate the page itself was behind (#2349).
bool _isUnderAny(Set<String> routes, String location) =>
    routes.any((route) => location == route || location.startsWith('$route/'));

/// How the gate below asks the Quark for its beta feature flags. A `var` so
/// tests can answer without a server, like [authStatusProbe].
Future<List<FeatureFlag>> Function() featureFlagsProbe =
    FeatureFlagsService.list;

/// Whether the Quark says the flag [key] is on. False when it cannot say.
Future<bool> _featureIsEnabled(String key) async {
  try {
    return (await featureFlagsProbe()).any(
      (flag) => flag.key == key && flag.enabled,
    );
  } catch (_) {
    return false;
  }
}

/// Whether the Quark says the signed-in caller is an admin. False when it
/// cannot say.
Future<bool> _callerIsAdmin() async {
  try {
    return (await authStatusProbe()).isAdmin;
  } catch (_) {
    return false;
  }
}

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
    return destinationAfterSignIn(
      state.uri.queryParameters[AppRoutes.loginFromParam],
    );
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
  const publicRoutes = {
    AppRoutes.setup,
    AppRoutes.recover,
    AppRoutes.forgotPassword,
    AppRoutes.requestAccount,
  };
  if (_isUnderAny(publicRoutes, location)) return null;

  // Admin-only pages (#1928). [AppSettings.isAdmin] is not persisted and
  // starts false on every launch, so trusting it would bounce an admin who
  // opens one of these from a link; the Quark is asked instead. A failed call
  // counts as no: the page could only render refusals.
  if (AppSettings.instance.sessionToken != null &&
      _isUnderAny(adminRoutes, location)) {
    if (await _callerIsAdmin()) return null;
    // Said, not just done: someone following an admin's link otherwise
    // lands in Files with no idea why (#2477). Shown after the frame that
    // builds Files: on a cold deep link there is no Scaffold to show it in
    // until then.
    final messenger = context.mounted
        ? ScaffoldMessenger.maybeOf(context)
        : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (messenger == null || !messenger.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(Errors.adminOnly)));
    });
    return AppRoutes.files;
  }

  // The betas an admin can turn off (#2421, #2609). Asked of the Quark like
  // the admin pages above: a link or a reload must not open a page whose
  // every request would 404.
  for (final (route, flag) in const [
    (AppRoutes.chat, FeatureFlag.chat),
    (AppRoutes.calendar, FeatureFlag.calendar),
  ]) {
    if (AppSettings.instance.sessionToken != null &&
        _isUnderAny({route}, location)) {
      return await _featureIsEnabled(flag) ? null : AppRoutes.files;
    }
  }

  // Already authenticated.
  if (AppSettings.instance.sessionToken != null) return null;

  final destination = await destinationForSignedOutUser();
  // /login is public, so "stay put" is a real answer here — returning the
  // location we are already at would be a redirect loop.
  if (destination == location) return null;
  // The link they followed rides along, so signing in returns to it (#2500).
  return destination == AppRoutes.login
      ? AppRoutes.loginFrom(state.uri.toString())
      : destination;
}

/// Where signing in lands: [from], the location a signed-out visitor asked
/// for, when it is a path inside the app (#2500), and Files otherwise. Another
/// site, a `//host` link or the login page itself all mean Files, so a crafted
/// link can't send a fresh sign-in anywhere else.
String destinationAfterSignIn(String? from) {
  final uri = Uri.tryParse(from ?? '');
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      _isUnderAny({AppRoutes.login}, uri.path)) {
    return AppRoutes.files;
  }
  return uri.toString();
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
