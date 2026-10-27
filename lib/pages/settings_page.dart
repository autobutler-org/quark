import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/change_password_controller.dart';
import 'package:quark/controllers/feature_flags_controller.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/controllers/remote_access_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/connected_devices_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/sbom_service.dart';
import 'package:quark/services/settings_service.dart';
import 'package:quark/services/users_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/music/music_rescan_card.dart';
import 'package:quark/widgets/notifications/notification_preferences_card.dart';
import 'package:quark/widgets/settings/change_password/change_password_dialog.dart';
import 'package:quark/widgets/settings/connected_devices_card.dart';
import 'package:quark/widgets/settings/remote_access_card.dart';
import 'package:quark/widgets/settings/remote_access_setup_sheet.dart';
import 'package:quark/widgets/settings/settings_about_tab.dart';
import 'package:quark/widgets/settings/sessions_section.dart';
import 'package:quark/widgets/settings/settings_account_tab.dart';
import 'package:quark/widgets/settings/settings_features_tab.dart';
import 'package:quark/widgets/settings/settings_general_tab.dart';
import 'package:quark/widgets/settings/settings_network_tab.dart';
import 'package:quark/widgets/settings/this_phone_card.dart';
import 'package:quark/widgets/settings/settings_profile_card.dart';
import 'package:quark/widgets/settings/settings_updates_tab.dart';

/// The commit a `make serve/...` or `make watch/frontend` run was built from.
///
/// Empty in a released build, which is identified by its tag instead. Const
/// because `--dart-define` is a compile-time constant, so a release build
/// drops the branch that reads it.
const gitSha = String.fromEnvironment('GIT_SHA');

/// This app's version, as `--build-name` stamped it, or empty when the build
/// passed none. `flutter build` and `flutter run` define it, the same value
/// the platform bundle carries.
const appBuildName = String.fromEnvironment('FLUTTER_BUILD_NAME');

/// This app's build number, as `--build-number` stamped it, or empty.
const appBuildNumber = String.fromEnvironment('FLUTTER_BUILD_NUMBER');

/// How one build identifies itself — this app's, or the Quark's (#1606).
///
/// Both sit in Settings and a bug report quotes both, so they must not
/// describe the same situation two different ways. The Quark's used to read
/// `dev (untagged)` where the app read `Development build`.
///
/// [version] arrives empty more often than it looks like it would. On this
/// app, `pubspec.yaml` deliberately carries no `version:` — the Makefile
/// derives it from the git tag instead — so nothing is stamped unless the
/// build passed `--build-name`. On the Quark, the `NOSEMVER` sentinel means
/// the same thing.
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

/// How often Settings asks for the installed version while a restart is in
/// progress. A test passes a shorter one.
const _updateRestartPoll = Duration(seconds: 1);

/// How long Settings waits for the restarted Quark to report the version it
/// just installed. Long enough for a container to exit and come back (#3218).
const _updateRestartTimeout = Duration(seconds: 90);

/// Whether [reported] is the release [requested], ignoring one leading "v".
/// The available-version list and the installed semver don't always agree on
/// that prefix.
bool _sameQuarkRelease(String? reported, String requested) {
  if (reported == null || reported.isEmpty || reported == 'NOSEMVER') {
    return false;
  }
  String number(String value) {
    final trimmed = value.trim();
    return trimmed.startsWith('v') ? trimmed.substring(1) : trimmed;
  }

  return number(reported) == number(requested);
}

/// The Settings page, in tabs that each have their own URL (#2350): General
/// (backend hosts, theme, auto-refresh, demo mode, a link to the drives),
/// Account (sign out, then deleting the account and resetting the Quark),
/// Network (remote access, connected devices, SSH), Updates (the Quark's
/// version, updates, repair) and About (the app's version, help and terms,
/// the software bill of materials), and Features (a switch per beta feature
/// flag, #2542). SSH access, updating, repair, reset and
/// the Features tab are admin-only, and Features shows only while the Quark
/// has betas.
///
/// The router passes the [tab] to show and [onTabSelected] to move to
/// another. The page loads every tab's data up front, so one unreachable
/// Quark raises one banner above the tabs whichever is showing.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    this.tab = SettingsTab.general,
    this.onTabSelected,
    this.featureFlags,
    this.getInstalledVersion,
    this.listAvailableVersions,
    this.updateToVersion,
    this.restartPollInterval = _updateRestartPoll,
    this.restartTimeout = _updateRestartTimeout,
    super.key,
  });

  /// Drives the Features tab. Null builds one over the real service; a test
  /// passes one with a fake.
  final FeatureFlagsController? featureFlags;

  /// Reads the installed version. Null calls [FilesService.getInstalledVersion].
  /// A test passes a fake.
  final Future<Map<String, dynamic>> Function()? getInstalledVersion;

  /// Lists versions the Quark can update to. Null calls
  /// [FilesService.listAvailableVersions]. A test passes a fake.
  final Future<List<Map<String, dynamic>>> Function()? listAvailableVersions;

  /// Installs [version]. Null calls [FilesService.updateToVersion]. A test
  /// passes a fake.
  final Future<void> Function(String version)? updateToVersion;

  /// How often to ask for the installed version while the Quark restarts.
  final Duration restartPollInterval;

  /// How long to wait for the restarted Quark to report the requested version.
  final Duration restartTimeout;

  /// The tab to show.
  final SettingsTab tab;

  /// Called with the tab the user picked. Null keeps the choice in the view.
  final ValueChanged<SettingsTab>? onTabSelected;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final FeatureFlagsController _features =
      widget.featureFlags ?? FeatureFlagsController();

  String? _installedVersion;

  /// Where [_installedVersion]'s release notes live, or null for a dev build.
  String? _installedReleaseUrl;
  List<String> _availableVersions = [];
  String? _selectedUpdateVersion;
  bool _isLoadingVersionInfo = false;
  bool _isUpdatingVersion = false;
  bool _isRestarting = false;
  String? _updateError;
  String? _versionLoadError;

  bool _highContrast = false;
  bool _demoMode = false;

  GoSbom? _goSbom;
  List<FlutterPackage>? _flutterSbom;
  bool _isLoadingSbom = false;
  String? _sbomError;

  int _refreshIntervalSeconds = 15;

  /// Remote access on the Network tab (#2857).
  final RemoteAccessController _remoteAccess = RemoteAccessController();

  /// Whether this visit already offered setup for a stored flag that never
  /// enrolled. Once is enough: dismissing the sheet must not reopen it.
  bool _offeredRemoteAccessSetup = false;

  List<ConnectedDevice> _connectedDevices = [];
  bool _isLoadingDevices = false;
  String? _devicesError;

  bool _avatarBusy = false;
  String? _avatarError;

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

  /// Everything the theme controls show: the mode the app bar toggle also
  /// changes (#2053), and the theme color pickers' state (#2740). The
  /// left-handed switch (#1812) and the view Calendar opens on (#2521) ride
  /// along.
  final Listenable _themeColors = Listenable.merge([
    AppSettings.instance.themeMode,
    AppSettings.instance.leftHanded,
    AppSettings.instance.defaultCalendarView,
    AppSettings.instance.themeColor,
    AppSettings.instance.quarkThemeColor,
    AppSettings.instance.userThemeColor,
    AppSettings.instance.sessionTokenNotifier,
  ]);

  @override
  void initState() {
    super.initState();
    // Admin-only actions appear and disappear as the Quark reports the role.
    AppSettings.instance.isAdmin.addListener(_onAdminChanged);
    _features.addListener(_onAdminChanged);
    // The theme controls follow the theme as it is fetched, saved and toggled.
    _themeColors.addListener(_onAdminChanged);
    _load();
  }

  void _onAdminChanged() {
    if (mounted) setState(() {});
  }

  void _load() {
    _refreshIntervalSeconds = AppSettings.instance.refreshIntervalSeconds;
    _highContrast = AppSettings.instance.highContrast.value;
    _demoMode = AppSettings.instance.demoMode.value;
    // Cleared up front so removing the last host retires the banner: with no
    // host every loader below returns early and none would ever clear it.
    _disconnected = false;
    setState(() {});
    _loadVersionInfo();
    _loadSbom();
    _loadDevices();
    _loadRemoteAccess();
  }

  Future<void> _loadRemoteAccess() async {
    if (AppSettings.instance.activeHost == null) {
      _remoteAccess.clear();
      return;
    }
    await _remoteAccess.load();
    if (!mounted) return;
    _noteReachability(_remoteAccess.loadFailure);
    _offerRemoteAccessSetup();
  }

  /// Opens the setup sheet when the stored flag is on but enrollment never
  /// finished. The sheet waits for Turn on. This does not enable remote
  /// access (#3611).
  void _offerRemoteAccessSetup() {
    if (_offeredRemoteAccessSetup || !mounted) return;
    final status = _remoteAccess.status;
    if (status == null || !status.needsSetup) return;
    if (!AppSettings.instance.isAdmin.value) return;
    _offeredRemoteAccessSetup = true;
    _setUpRemoteAccess();
  }

  /// Opens the remote access setup sheet.
  void _setUpRemoteAccess() =>
      showRemoteAccessSetupSheet(context, _remoteAccess);

  /// Turns remote access on again after it failed to connect.
  Future<void> _retryRemoteAccess() async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await _remoteAccess.enable();
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  /// Confirms, then turns remote access off for the whole household.
  Future<void> _turnOffRemoteAccess() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => RemoteAccessTurnOffDialog(
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final error = await _remoteAccess.disable();
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'Remote access is off')),
    );
  }

  /// Turns a beta feature on or off for everyone on this Quark (#2542).
  Future<void> _setFeature(String key, bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await _features.setFlag(key, enabled);
    if (error != null && mounted) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
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
      showMessage(context, Errors.message(e, 'remove the device'));
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
      final installed = await _fetchInstalledVersion();
      final versions = await _fetchAvailableVersions();
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

  Future<Map<String, dynamic>> _fetchInstalledVersion() {
    final fetch = widget.getInstalledVersion;
    if (fetch != null) return fetch();
    return FilesService.getInstalledVersion();
  }

  Future<List<Map<String, dynamic>>> _fetchAvailableVersions() {
    final fetch = widget.listAvailableVersions;
    if (fetch != null) return fetch();
    return FilesService.listAvailableVersions();
  }

  Future<void> _requestUpdate(String version) {
    final update = widget.updateToVersion;
    if (update != null) return update(version);
    return FilesService.updateToVersion(version);
  }

  String? _semverOf(Map<String, dynamic> installed) =>
      (installed['semver'] as String?) ?? (installed['version'] as String?);

  /// Polls until the Quark reports [requested], including while the restart
  /// takes the server down. The POST returns while the old process is still
  /// serving (#3218), so the first answer is not the result.
  Future<bool> _waitForRestartedVersion(String requested) async {
    final intervalMs = widget.restartPollInterval.inMilliseconds;
    final timeoutMs = widget.restartTimeout.inMilliseconds;
    final attempts = intervalMs <= 0
        ? 1
        : (timeoutMs ~/ intervalMs).clamp(1, 1 << 30);
    for (var i = 0; i < attempts; i++) {
      await Future<void>.delayed(widget.restartPollInterval);
      if (!mounted) return false;
      try {
        final installed = await _fetchInstalledVersion();
        if (_sameQuarkRelease(_semverOf(installed), requested)) return true;
      } catch (_) {
        // The restart takes the server down. Keep waiting for it to come back.
      }
    }
    return false;
  }

  Future<void> _performUpdate() async {
    final version = _selectedUpdateVersion;
    if (version == null || _isUpdatingVersion || _isRestarting) return;

    setState(() {
      _isUpdatingVersion = true;
      _updateError = null;
    });

    try {
      await _requestUpdate(version);
    } catch (e) {
      debugPrint('[settings_page.dart] Error: $e');
      if (!mounted) return;
      setState(() => _isUpdatingVersion = false);
      showMessage(context, Errors.update(e));
      return;
    }
    if (!mounted) return;

    setState(() {
      _isUpdatingVersion = false;
      _isRestarting = true;
    });

    final arrived = await _waitForRestartedVersion(version);
    if (!mounted) return;
    if (!arrived) {
      setState(() {
        _isRestarting = false;
        _updateError = Errors.updateDidNotFinish;
      });
      return;
    }

    setState(() {
      _isRestarting = false;
      _updateError = null;
    });
    await _loadVersionInfo();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final hasHost = settings.activeHost != null;
    final isAdmin = settings.isAdmin.value;
    final showFeatures = isAdmin && hasHost && _features.flags.isNotEmpty;
    // Heads every tab, since it explains every "Not connected" row and the
    // address it points at is on General (#1637). It scrolls with the tab's
    // content: pinned above the tabs, it left a phone almost no room.
    final banner = _disconnected
        ? QuarkDisconnectedBanner(onRetry: _load)
        : null;
    return QuarkPageScaffold(
      title: 'Settings',
      icon: QuarkIcons.settings_outlined,
      actions: const [AppThemeToggle()],
      drawer: const AppDrawer(activeSection: QuarkDrawerSection.settings),
      body: QuarkTabView(
        // Features is the last tab, so while it is hidden a link to it shows
        // General and every other index still lines up.
        selectedIndex: showFeatures || widget.tab != SettingsTab.features
            ? widget.tab.index
            : 0,
        onTabSelected: widget.onTabSelected == null
            ? null
            : (index) => widget.onTabSelected!(SettingsTab.values[index]),
        tabs: [
          QuarkTab(
            label: 'General',
            child: SettingsGeneralTab(
              header: banner,
              theme: settings.themeMode.value,
              onThemeChanged: settings.setThemeMode,
              highContrast: _highContrast,
              onHighContrastChanged: _setHighContrast,
              leftHanded: settings.leftHanded.value,
              onLeftHandedChanged: settings.setLeftHanded,
              themeColor: settings.themeColor.value,
              followsQuarkThemeColor:
                  (settings.userThemeColor.value ?? '').isEmpty,
              quarkThemeColor: QuarkThemeColor.parse(
                settings.quarkThemeColor.value,
              ),
              onThemeColorChanged: hasHost && settings.sessionToken != null
                  ? _setThemeColor
                  : null,
              onQuarkThemeColorChanged: hasHost && isAdmin
                  ? _setQuarkThemeColor
                  : null,
              defaultCalendarView: settings.defaultCalendarView.value,
              onDefaultCalendarViewChanged: settings.setDefaultCalendarView,
              // Every type today is a backup reminder, which only an admin
              // receives, so only an admin has anything to switch (#2493).
              notifications: hasHost && isAdmin && settings.sessionToken != null
                  ? NotificationPreferencesCard(
                      controller: NotificationsController.instance,
                    )
                  : null,
              refreshIntervalSeconds: _refreshIntervalSeconds,
              onRefreshIntervalChanged: _setRefreshInterval,
              demoMode: _demoMode,
              onDemoModeChanged: _setDemoMode,
              onHostsChanged: _load,
              onOpenStorage: hasHost
                  ? () => context.go(AppRoutes.systemTab(SystemTab.storage))
                  : null,
              musicLibrary: hasHost && isAdmin ? const MusicRescanCard() : null,
            ),
          ),
          QuarkTab(
            label: 'Account',
            child: SettingsAccountTab(
              header: banner,
              profile: ListenableBuilder(
                listenable: Listenable.merge([
                  AppSettings.instance.userId,
                  AppSettings.instance.avatarUpdatedAt,
                ]),
                builder: (context, _) => SettingsProfileCard(
                  userId: AppSettings.instance.userId.value,
                  username: AppSettings.instance.username ?? '',
                  avatarVersion: AppSettings.instance.avatarUpdatedAt.value,
                  isBusy: _avatarBusy,
                  error: _avatarError,
                  onPick: _pickAvatar,
                  onRemove: _removeAvatar,
                ),
              ),
              signedIn: AppSettings.instance.sessionToken != null,
              isAdmin: isAdmin,
              onSignOut: _signOut,
              onChangePassword: _changePassword,
              sessions: SessionsSection(
                onSignedOut: () => context.go(AppRoutes.files),
              ),
              onOpenAccountAndData: () =>
                  context.push(AppRoutes.accountAndData),
              onOpenUsers: () => context.go(AppRoutes.users),
            ),
          ),
          QuarkTab(
            label: 'Network',
            child: SettingsNetworkTab(
              header: banner,
              hasHost: hasHost,
              isAdmin: isAdmin,
              remoteAccess: ListenableBuilder(
                listenable: _remoteAccess,
                builder: (context, _) => RemoteAccessCard(
                  status: _remoteAccess.status,
                  isLoading: _remoteAccess.isLoading,
                  isWorking: _remoteAccess.isWorking,
                  error: _remoteAccess.error,
                  disconnected: _disconnected,
                  isAdmin: isAdmin,
                  onRetry: _loadRemoteAccess,
                  onSetUp: _setUpRemoteAccess,
                  onTurnOff: _turnOffRemoteAccess,
                  onTryAgain: _retryRemoteAccess,
                ),
              ),
              thisPhone: kIsWeb ? null : const ThisPhoneCard(),
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
              isRestarting: _isRestarting,
              versionError: _versionLoadError,
              updateError: _updateError,
              onSelectVersion: (v) =>
                  setState(() => _selectedUpdateVersion = v),
              onUpdate: _performUpdate,
              onOpenReleaseNotes: _openReleaseNotes,
            ),
          ),
          QuarkTab(
            label: 'About',
            child: SettingsAboutTab(
              header: banner,
              // Distinct from the Quark's own version: a bug report names
              // both (#1606).
              appVersion: appVersionLabel(
                version: appBuildName,
                buildNumber: appBuildNumber,
              ),
              appReleaseUrl: releaseNotesUrl(appBuildName),
              onOpenReleaseNotes: _openReleaseNotes,
              onOpenTerms: () => context.push(AppRoutes.terms),
              isLoadingSbom: _isLoadingSbom,
              sbomError: _sbomError,
              flutterSbom: _flutterSbom,
              goSbom: _goSbom,
            ),
          ),
          if (showFeatures)
            QuarkTab(
              label: 'Features',
              child: SettingsFeaturesTab(
                header: banner,
                flags: _features.flags,
                isSaving: _features.isSaving,
                onChanged: _setFeature,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _setHighContrast(bool enabled) async {
    setState(() => _highContrast = enabled);
    await AppSettings.instance.setHighContrast(enabled);
  }

  Future<void> _setRefreshInterval(int seconds) async {
    await AppSettings.instance.setRefreshIntervalSeconds(seconds);
    if (mounted) setState(() => _refreshIntervalSeconds = seconds);
  }

  Future<void> _setDemoMode(bool enabled) async {
    setState(() => _demoMode = enabled);
    await AppSettings.instance.setDemoMode(enabled);
  }

  /// Saves the user's own theme color, empty to follow the Quark's.
  Future<void> _setThemeColor(String themeColor) => _saveThemeColor(
    themeColor,
    apply: AppSettings.instance.setUserThemeColor,
    save: SettingsService.setMyThemeColor,
    action: 'save your theme color',
  );

  /// Saves the Quark's default theme color, as an admin.
  Future<void> _setQuarkThemeColor(String themeColor) => _saveThemeColor(
    themeColor,
    apply: AppSettings.instance.setQuarkThemeColor,
    save: SettingsService.setQuarkThemeColor,
    action: "save this Quark's theme color",
  );

  /// Applies [themeColor] at once and saves it, putting the theme color back as
  /// it was if the Quark refuses.
  Future<void> _saveThemeColor(
    String themeColor, {
    required Future<void> Function(String?) apply,
    required Future<void> Function(String) save,
    required String action,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final restore = AppSettings.instance.snapshotThemeColor();
    await apply(themeColor);
    try {
      await save(themeColor);
    } catch (e) {
      debugPrint('[settings_page.dart] Error saving theme color: $e');
      await restore();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(Errors.message(e, action))),
      );
    }
  }

  /// Picks an image and uploads it as the user's profile picture, streaming
  /// it off the device rather than reading it into memory.
  Future<void> _pickAvatar() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null || !mounted) return;
    await _changeAvatar('change your picture', () async {
      // A platform that can't say how long the file is gets it read whole;
      // a multipart upload has to declare its length up front.
      final length = await file.length();
      final whole = length == null ? await file.readAsBytes() : null;
      await UsersService.setAvatar(
        bytes: whole == null ? file.readAsByteStream() : Stream.value(whole),
        length: length ?? whole!.length,
        filename: file.name,
      );
    });
  }

  Future<void> _removeAvatar() =>
      _changeAvatar('remove your picture', UsersService.removeAvatar);

  /// Runs [change] with the Profile card busy, and shows why it failed.
  Future<void> _changeAvatar(
    String action,
    Future<void> Function() change,
  ) async {
    setState(() {
      _avatarBusy = true;
      _avatarError = null;
    });
    String? error;
    try {
      await change();
    } catch (e) {
      error = Errors.avatar(e, action);
    }
    if (!mounted) return;
    setState(() {
      _avatarBusy = false;
      _avatarError = error;
    });
  }

  /// Shows the change-password dialog (#3022), which stays up while the
  /// change runs and closes only once it has gone through.
  Future<void> _changePassword() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ChangePasswordController();
    final changed = await showDialog<bool>(
      context: context,
      // A stray tap outside must not drop three typed passwords.
      barrierDismissible: false,
      builder: (ctx) => ListenableBuilder(
        listenable: controller,
        builder: (ctx, _) => ChangePasswordDialog(
          isWorking: controller.isWorking,
          error: controller.error,
          onCancel: () => Navigator.of(ctx).pop(),
          onSubmit: (currentPassword, newPassword) async {
            final ok = await controller.changePassword(
              currentPassword: currentPassword,
              newPassword: newPassword,
            );
            if (ok && ctx.mounted) Navigator.of(ctx).pop(true);
          },
        ),
      ),
    );
    controller.dispose();
    if (changed == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Password changed')));
    }
  }

  Future<void> _signOut() async {
    final confirmed = await confirmAction(
      context,
      title: 'Sign out',
      message: 'Are you sure you want to sign out?',
      confirmLabel: 'Sign out',
    );
    if (confirmed != true || !mounted) return;
    await AuthService.logout();
    if (!mounted) return;
    if (mounted) context.go(AppRoutes.files);
  }

  @override
  void dispose() {
    AppSettings.instance.isAdmin.removeListener(_onAdminChanged);
    _features.removeListener(_onAdminChanged);
    _themeColors.removeListener(_onAdminChanged);
    if (widget.featureFlags == null) _features.dispose();
    _remoteAccess.dispose();
    super.dispose();
  }
}
