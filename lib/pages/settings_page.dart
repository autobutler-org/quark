import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/connected_devices_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/services/sbom_service.dart';
import 'package:quark/services/settings_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/remote_access_config.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/settings/connected_devices_card.dart';
import 'package:quark/widgets/settings/remote_access_card.dart';
import 'package:quark/widgets/settings/settings_about_tab.dart';
import 'package:quark/widgets/settings/settings_account_tab.dart';
import 'package:quark/widgets/settings/settings_general_tab.dart';
import 'package:quark/widgets/settings/settings_network_tab.dart';
import 'package:quark/widgets/settings/settings_updates_tab.dart';

/// The commit a `make serve/...` or `make watch/frontend` run was built from.
///
/// Empty in a released build, which is identified by its tag instead. Const
/// because `--dart-define` is a compile-time constant, so a release build
/// drops the branch that reads it.
const gitSha = String.fromEnvironment('GIT_SHA');

/// How one build identifies itself — this app's, or the Quark's (#1606).
///
/// Both sit in Settings and a bug report quotes both, so they must not
/// describe the same situation two different ways. The Quark's used to read
/// `dev (untagged)` where the app read `Development build`.
///
/// [version] arrives empty more often than it looks like it would. On this
/// app, `pubspec.yaml` deliberately carries no `version:` — the Makefile
/// derives it from the git tag instead — so nothing is stamped unless the
/// build passed `--build-name`; web is emptier still, its `version.json`
/// omitting the keys outright rather than defaulting them. On the Quark, the
/// `NOSEMVER` sentinel means the same thing.
///
/// Which build the reader is holding decides what identifies it:
///
/// - One built from a tag is that tag, plus a build number when one was
///   stamped — only the iOS release asks App Store Connect for one.
/// - A dev build has no tag on purpose, since something built from a dirty
///   tree reporting a released version is the ambiguity this is meant to
///   remove. It names its commit, the only thing telling it from any other.
String buildVersionLabel({
  required String version,
  String buildNumber = '',
  String sha = '',
}) {
  if (version.isEmpty) {
    return sha.isEmpty
        ? 'Development build — no version stamped'
        : 'Development build ($sha)';
  }
  if (buildNumber.isEmpty) return version;
  return '$version ($buildNumber)';
}

/// The app's own row, which has to name what it is reporting.
///
/// Always prefixed, dev builds included. Both this and the Quark's version
/// render as `Development build (<sha>)` on a developer's machine, from two
/// different commits — the app is whatever the dev server compiled, the Quark
/// whatever binary is running — and two identical-looking lines with
/// different hashes read as the page contradicting itself (#2035). The colon
/// is what lets the prefix sit in front of "Development build" without
/// reading like a bug.
String appVersionLabel({
  required String version,
  required String buildNumber,
  String sha = gitSha,
}) {
  final label = buildVersionLabel(
    version: version,
    buildNumber: buildNumber,
    sha: sha,
  );
  return 'App version: $label';
}

/// The GitHub release a tagged build was cut from, or null when there is no
/// release to link to (#1756).
///
/// A dev build is untagged on purpose, so no release page exists for it: the
/// app says so by stamping no version at all and the Quark by answering with
/// its `NOSEMVER` sentinel. Tags carry the `v` prefix that the Makefile strips
/// out of `--build-name`, so it goes back on whichever form arrives.
String? releaseNotesUrl(String version) {
  final tag = version.trim();
  if (tag.isEmpty || tag == 'NOSEMVER') return null;
  return 'https://github.com/autobutler-org/quark/releases/tag/'
      '${tag.startsWith('v') ? tag : 'v$tag'}';
}

/// The Quark reports a full commit, and the `NOCOMMIT` sentinel when its build
/// carried none. Seven characters is what the rest of the tooling shows.
String shortGitSha(String commit) => (commit.isEmpty || commit == 'NOCOMMIT')
    ? ''
    : commit.substring(0, commit.length.clamp(0, 7));

/// The Settings page, in tabs that each have their own URL (#2350): General
/// (backend hosts, theme, auto-refresh, demo mode, a link to the drives),
/// Account (sign out, then deleting the account and resetting the Quark),
/// Network (remote access, connected devices, SSH), Updates (the Quark's
/// version, updates, repair) and About (the app's version, help and terms,
/// the software bill of materials). SSH access, updating, automatic updates,
/// repair and reset are admin-only.
///
/// The router passes the [tab] to show and [onTabSelected] to move to
/// another. The page loads every tab's data up front, so one unreachable
/// Quark raises one banner above the tabs whichever is showing.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    this.tab = SettingsTab.general,
    this.onTabSelected,
    super.key,
  });

  /// The tab to show.
  final SettingsTab tab;

  /// Called with the tab the user picked. Null keeps the choice in the view.
  final ValueChanged<SettingsTab>? onTabSelected;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ThemeMode _theme = ThemeMode.system;

  /// How this app's own version reads, per [appVersionLabel] (#1606).
  ///
  /// Distinct from [_installedVersion], which is the Quark server's — a bug
  /// report needs to name both. Null until read, and stays null where no
  /// bundle answers at all (a unit test, a shell that was never packaged), in
  /// which case the row simply doesn't render.
  String? _appVersion;

  /// Where [_appVersion]'s release notes live, or null for a dev build.
  String? _appReleaseUrl;

  String? _installedVersion;

  /// Where [_installedVersion]'s release notes live, or null for a dev build.
  String? _installedReleaseUrl;
  List<String> _availableVersions = [];
  String? _selectedUpdateVersion;
  bool _isLoadingVersionInfo = false;
  bool _isUpdatingVersion = false;
  String? _versionLoadError;

  bool _autoUpdate = false;
  String? _autoUpdateError;
  bool _isLoadingAutoUpdate = false;

  bool _demoMode = false;

  // SBOM state
  GoSbom? _goSbom;
  List<FlutterPackage>? _flutterSbom;
  bool _isLoadingSbom = false;
  String? _sbomError;

  int _refreshIntervalSeconds = 15;

  RemoteAccessStatus? _remoteAccessStatus;
  bool _isLoadingRemoteAccess = false;
  bool _isTogglingRemoteAccess = false;
  String? _remoteAccessError;

  /// Re-reads the status while remote access is on but not yet connected, so
  /// "Connecting…" resolves without a reload (#1876).
  Timer? _remoteAccessPoll;

  // Connected devices state
  List<ConnectedDevice> _connectedDevices = [];
  bool _isLoadingDevices = false;
  String? _devicesError;

  /// Whether the last section load failed to reach the Quark at all (#1637).
  ///
  /// Page-level rather than per-section: every section talks to the same
  /// Quark, so one unreachable section means they all are, and one banner
  /// explains it once instead of six rows each repeating a socket error. This
  /// page keeps working while disconnected on purpose — host management lives
  /// on it, and it is where the address gets fixed.
  bool _disconnected = false;

  /// Records whether a section's load reached the Quark.
  ///
  /// Pass the thrown object, or null on success. A section that succeeded
  /// proves the Quark is reachable, so success clears the banner even if
  /// another section is still failing for its own reasons.
  void _noteReachability(Object? error) {
    if (!mounted) return;
    final disconnected = error != null && isQuarkUnreachableError(error);
    if (disconnected == _disconnected) return;
    setState(() => _disconnected = disconnected);
  }

  @override
  void initState() {
    super.initState();
    // Admin-only actions appear and disappear as the Quark reports the role.
    AppSettings.instance.isAdmin.addListener(_onAdminChanged);
    _load();
  }

  void _onAdminChanged() {
    if (mounted) setState(() {});
  }

  void _load() {
    _theme = AppSettings.instance.themeMode.value;
    _refreshIntervalSeconds = AppSettings.instance.refreshIntervalSeconds;
    _demoMode = AppSettings.instance.demoMode.value;
    // Cleared up front so removing the last host retires the banner: with no
    // host every loader below returns early and none would ever clear it.
    _disconnected = false;
    setState(() {});
    _loadAppVersion();
    _loadVersionInfo();
    _loadSettings();
    _loadSbom();
    _loadDevices();
    _loadRemoteAccess();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = appVersionLabel(
          version: info.version,
          buildNumber: info.buildNumber,
        );
        _appReleaseUrl = releaseNotesUrl(info.version);
      });
    } catch (_) {
      // Nothing to report and nothing to retry: without a bundle to read there
      // is no app version, so the row stays hidden rather than showing an error
      // about a number the user cannot act on.
    }
  }

  Future<void> _loadRemoteAccess() async {
    if (AppSettings.instance.activeHost == null) {
      setState(() {
        _remoteAccessStatus = null;
        _remoteAccessError = null;
        _isLoadingRemoteAccess = false;
      });
      _syncRemoteAccessPoll();
      return;
    }
    setState(() {
      _isLoadingRemoteAccess = true;
      _remoteAccessError = null;
    });
    try {
      final status = await RemoteAccessService.getStatus();
      if (status.error != null) {
        debugPrint(
          '[settings_page.dart] Remote access failing: ${status.error}',
        );
      }
      if (!mounted) return;
      setState(() {
        _remoteAccessStatus = status;
        _isLoadingRemoteAccess = false;
      });
      _syncRemoteAccessPoll();
      _noteReachability(null);
    } catch (e) {
      debugPrint('[settings_page.dart] Remote access error: $e');
      if (!mounted) return;
      setState(() {
        _remoteAccessError = Errors.message(e, 'load remote access status');
        _isLoadingRemoteAccess = false;
      });
      _noteReachability(e);
    }
  }

  /// Starts the status poll while remote access is on and not connected, and
  /// stops it otherwise.
  void _syncRemoteAccessPoll() {
    final status = _remoteAccessStatus;
    if (status == null || !status.enabled || status.connected) {
      _remoteAccessPoll?.cancel();
      _remoteAccessPoll = null;
      return;
    }
    _remoteAccessPoll ??= Timer.periodic(
      RemoteAccessConfig.statusPollInterval,
      (_) => _pollRemoteAccess(),
    );
  }

  /// One quiet status read: no spinner, and a failure keeps the last status
  /// on screen for the next tick to replace.
  Future<void> _pollRemoteAccess() async {
    try {
      final status = await RemoteAccessService.getStatus();
      if (!mounted) return;
      setState(() {
        _remoteAccessStatus = status;
        _remoteAccessError = null;
      });
      _syncRemoteAccessPoll();
    } catch (e) {
      debugPrint('[settings_page.dart] Remote access poll failed: $e');
    }
  }

  Future<void> _enableRemoteAccess() async {
    setState(() => _isTogglingRemoteAccess = true);
    try {
      final status = await RemoteAccessService.enable();
      if (!mounted) return;
      setState(() {
        _remoteAccessStatus = status;
        _isTogglingRemoteAccess = false;
      });
      _syncRemoteAccessPoll();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Remote access enabled')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTogglingRemoteAccess = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'enable remote access'))),
      );
    }
  }

  Future<void> _disableRemoteAccess() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disable remote access'),
        content: const Text(
          'This will disconnect the Tailscale tunnel. '
          'You will no longer be able to reach this quark remotely. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isTogglingRemoteAccess = true);
    try {
      final status = await RemoteAccessService.disable();
      if (!mounted) return;
      setState(() {
        _remoteAccessStatus = status;
        _isTogglingRemoteAccess = false;
      });
      _syncRemoteAccessPoll();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Remote access disabled')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTogglingRemoteAccess = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'disable remote access'))),
      );
    }
  }

  Future<void> _loadDevices() async {
    if (AppSettings.instance.activeHost == null) {
      setState(() {
        _connectedDevices = [];
        _devicesError = null;
        _isLoadingDevices = false;
      });
      return;
    }
    setState(() {
      _isLoadingDevices = true;
      _devicesError = null;
    });
    try {
      final devices = await ConnectedDevicesService.listDevices();
      if (!mounted) return;
      setState(() {
        _connectedDevices = devices;
        _isLoadingDevices = false;
      });
      _noteReachability(null);
    } catch (e) {
      debugPrint('[settings_page.dart] Error: $e');
      if (!mounted) return;
      setState(() {
        _devicesError = Errors.message(e, 'load your devices');
        _isLoadingDevices = false;
      });
      _noteReachability(e);
    }
  }

  Future<void> _deleteDevice(int id) async {
    try {
      await ConnectedDevicesService.deleteDevice(id);
      await _loadDevices();
    } catch (e) {
      debugPrint('[settings_page.dart] Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'remove the device'))),
      );
    }
  }

  Future<void> _loadSbom() async {
    setState(() {
      _isLoadingSbom = true;
      _sbomError = null;
    });

    GoSbom? nextGoSbom;
    List<FlutterPackage>? nextFlutterSbom;
    final errors = <String>[];

    if (AppSettings.instance.activeHost != null) {
      try {
        nextGoSbom = await SbomService.getGoSbom();
        _noteReachability(null);
      } catch (e) {
        debugPrint('[settings_page.dart] Error: $e');
        // The Go SBOM is the only source here that comes from the Quark, so
        // it is the only one an unreachable Quark explains (#1637).
        errors.add(Errors.message(e, 'load the Go SBOM'));
        _noteReachability(e);
      }
    }

    try {
      nextFlutterSbom = await SbomService.getFlutterSbom();
    } catch (e) {
      debugPrint('[settings_page.dart] Error: $e');
      errors.add(Errors.message(e, 'load the Flutter SBOM'));
    }

    if (!mounted) return;
    setState(() {
      _goSbom = nextGoSbom;
      _flutterSbom = nextFlutterSbom;
      _sbomError = errors.isEmpty ? null : errors.join('\n');
      _isLoadingSbom = false;
    });
  }

  Future<void> _loadSettings() async {
    if (AppSettings.instance.activeHost == null) return;
    setState(() {
      _isLoadingAutoUpdate = true;
    });
    try {
      final autoUpdate = await SettingsService.getAutoUpdate();
      if (!mounted) return;
      setState(() {
        _autoUpdate = autoUpdate;
        _autoUpdateError = null;
        _isLoadingAutoUpdate = false;
      });
      _noteReachability(null);
    } catch (e) {
      debugPrint('[settings_page.dart] Error loading settings: $e');
      if (!mounted) return;
      setState(() {
        _autoUpdateError = Errors.message(e, 'load the setting');
        _isLoadingAutoUpdate = false;
      });
      _noteReachability(e);
    }
  }

  Future<void> _loadVersionInfo() async {
    if (AppSettings.instance.activeHost == null) {
      setState(() {
        _installedVersion = null;
        _installedReleaseUrl = null;
        _availableVersions = const [];
        _selectedUpdateVersion = null;
        _versionLoadError = null;
        _isLoadingVersionInfo = false;
      });
      return;
    }

    setState(() {
      _isLoadingVersionInfo = true;
      _versionLoadError = null;
    });

    try {
      final installed = await FilesService.getInstalledVersion();
      final versions = await FilesService.listAvailableVersions();
      if (!mounted) return;

      // A missing field is not a dev build — it is a Quark that answered with
      // something this app cannot read, and saying so beats guessing.
      final semver =
          (installed['semver'] as String?) ?? (installed['version'] as String?);
      final installedVersion = semver == null
          ? 'Unknown'
          : buildVersionLabel(
              version: semver == 'NOSEMVER' ? '' : semver,
              sha: shortGitSha((installed['gitCommit'] as String?) ?? ''),
            );
      final availableVersions = versions
          .map((m) => (m['version'] as String?) ?? '')
          .where((v) => v.isNotEmpty)
          .toList(growable: false);
      final selectedVersion = availableVersions.contains(_selectedUpdateVersion)
          ? _selectedUpdateVersion
          : (availableVersions.isNotEmpty ? availableVersions.first : null);

      setState(() {
        _installedVersion = installedVersion;
        _installedReleaseUrl = releaseNotesUrl(semver ?? '');
        _availableVersions = availableVersions;
        _selectedUpdateVersion = selectedVersion;
        _isLoadingVersionInfo = false;
      });
      _noteReachability(null);
    } catch (e) {
      debugPrint('[settings_page.dart] Error: $e');
      if (!mounted) return;
      setState(() {
        _versionLoadError = Errors.message(e, 'load version info');
        _installedReleaseUrl = null;
        _isLoadingVersionInfo = false;
      });
      _noteReachability(e);
    }
  }

  Future<void> _openReleaseNotes(String url) {
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _performUpdate() async {
    final version = _selectedUpdateVersion;
    if (version == null || _isUpdatingVersion) return;

    setState(() {
      _isUpdatingVersion = true;
    });

    try {
      await FilesService.updateToVersion(version);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update started for $version')));
      await _loadVersionInfo();
    } catch (e) {
      debugPrint('[settings_page.dart] Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'start the update'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingVersion = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasHost = AppSettings.instance.activeHost != null;
    final isAdmin = AppSettings.instance.isAdmin.value;
    // Heads every tab, since it explains every "Not connected" row and the
    // address it points at is on General (#1637). It scrolls with the tab's
    // content: pinned above the tabs, it left a phone almost no room.
    final banner = _disconnected
        ? QuarkDisconnectedBanner(onRetry: _load)
        : null;
    return Scaffold(
      appBar: QuarkAppBar(
        label: 'Settings',
        icon: QuarkIcons.settings_outlined,
        actions: const [AppThemeToggle()],
      ),
      drawer: const AppDrawer(activeSection: QuarkDrawerSection.settings),
      body: QuarkTabView(
        selectedIndex: widget.tab.index,
        onTabSelected: widget.onTabSelected == null
            ? null
            : (index) => widget.onTabSelected!(SettingsTab.values[index]),
        tabs: [
          QuarkTab(
            label: 'General',
            child: SettingsGeneralTab(
              header: banner,
              theme: _theme,
              onThemeChanged: _setTheme,
              refreshIntervalSeconds: _refreshIntervalSeconds,
              onRefreshIntervalChanged: _setRefreshInterval,
              demoMode: _demoMode,
              onDemoModeChanged: _setDemoMode,
              onHostsChanged: _load,
              onOpenStorage: hasHost
                  ? () => context.go(AppRoutes.systemTab(SystemTab.storage))
                  : null,
            ),
          ),
          QuarkTab(
            label: 'Account',
            child: SettingsAccountTab(
              header: banner,
              signedIn: AppSettings.instance.sessionToken != null,
              isAdmin: isAdmin,
              onSignOut: _signOut,
              onOpenAccountAndData: () =>
                  context.push(AppRoutes.accountAndData),
            ),
          ),
          QuarkTab(
            label: 'Network',
            child: SettingsNetworkTab(
              header: banner,
              hasHost: hasHost,
              isAdmin: isAdmin,
              remoteAccess: RemoteAccessCard(
                status: _remoteAccessStatus,
                isLoading: _isLoadingRemoteAccess,
                isToggling: _isTogglingRemoteAccess,
                error: _remoteAccessError,
                disconnected: _disconnected,
                isAdmin: isAdmin,
                onRetry: _loadRemoteAccess,
                onEnable: _enableRemoteAccess,
                onDisable: _disableRemoteAccess,
              ),
              connectedDevices: ConnectedDevicesCard(
                devices: _connectedDevices,
                isLoading: _isLoadingDevices,
                error: _devicesError,
                disconnected: _disconnected,
                isAdmin: isAdmin,
                onRefresh: _loadDevices,
                onRemove: _deleteDevice,
              ),
            ),
          ),
          QuarkTab(
            label: 'Updates',
            child: SettingsUpdatesTab(
              header: banner,
              hasHost: hasHost,
              isAdmin: isAdmin,
              disconnected: _disconnected,
              installedVersion: _installedVersion,
              installedReleaseUrl: _installedReleaseUrl,
              availableVersions: _availableVersions,
              selectedVersion: _selectedUpdateVersion,
              isLoadingVersion: _isLoadingVersionInfo,
              isUpdating: _isUpdatingVersion,
              versionError: _versionLoadError,
              onSelectVersion: (v) =>
                  setState(() => _selectedUpdateVersion = v),
              onUpdate: _performUpdate,
              onOpenReleaseNotes: _openReleaseNotes,
              autoUpdate: _autoUpdate,
              isLoadingAutoUpdate: _isLoadingAutoUpdate,
              autoUpdateError: _autoUpdateError,
              onAutoUpdateChanged: _setAutoUpdate,
            ),
          ),
          QuarkTab(
            label: 'About',
            child: SettingsAboutTab(
              header: banner,
              appVersion: _appVersion,
              appReleaseUrl: _appReleaseUrl,
              onOpenReleaseNotes: _openReleaseNotes,
              onOpenTerms: () => context.push(AppRoutes.terms),
              isLoadingSbom: _isLoadingSbom,
              sbomError: _sbomError,
              flutterSbom: _flutterSbom,
              goSbom: _goSbom,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setTheme(ThemeMode mode) async {
    await AppSettings.instance.setThemeMode(mode);
    if (mounted) setState(() => _theme = mode);
  }

  Future<void> _setRefreshInterval(int seconds) async {
    await AppSettings.instance.setRefreshIntervalSeconds(seconds);
    if (mounted) setState(() => _refreshIntervalSeconds = seconds);
  }

  Future<void> _setDemoMode(bool enabled) async {
    setState(() => _demoMode = enabled);
    await AppSettings.instance.setDemoMode(enabled);
  }

  /// Saves the automatic-updates switch, flipping it back if the Quark
  /// refuses.
  Future<void> _setAutoUpdate(bool enabled) async {
    setState(() => _autoUpdate = enabled);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SettingsService.setAutoUpdate(enabled);
    } catch (e) {
      debugPrint('[settings_page.dart] Error saving auto-update: $e');
      if (!mounted) return;
      setState(() => _autoUpdate = !enabled);
      messenger.showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'save the setting'))),
      );
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AuthService.logout();
    if (!mounted) return;
    if (mounted) context.go(AppRoutes.files);
  }

  @override
  void dispose() {
    AppSettings.instance.isAdmin.removeListener(_onAdminChanged);
    _remoteAccessPoll?.cancel();
    super.dispose();
  }
}
