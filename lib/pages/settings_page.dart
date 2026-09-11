import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:quark/controllers/account_actions_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/connected_devices_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/services/sbom_service.dart';
import 'package:quark/services/settings_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/host_manager.dart';
import 'package:quark/widgets/settings/help_support_card.dart';
import 'package:quark/widgets/settings/sbom_expansion_tile.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/settings/code_block.dart';
import 'package:quark/widgets/settings/delete_account_dialog.dart';
import 'package:quark/widgets/settings/reset_quark_dialog.dart';

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

/// The app's own row, which has to name what it is reporting — the Quark's
/// version sits under its own "Installed version" heading and does not.
///
/// Prefixed only when there is a version to prefix: "App version Development
/// build" reads like a bug.
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
  return version.isEmpty ? label : 'App version $label';
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

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ThemeMode _theme = ThemeMode.system;

  /// Owns the account actions' service calls, so this [State] does not (#1762).
  final _accountActions = AccountActionsController();

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

  // Connected devices state
  List<ConnectedDevice> _connectedDevices = [];
  bool _isLoadingDevices = false;
  String? _devicesError;

  // Storage devices state
  List<StorageDevice> _storageDevices = [];
  bool _isLoadingStorage = false;
  String? _storageError;

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
    _load();
  }

  void _load() {
    _theme = AppSettings.instance.themeMode.value;
    _refreshIntervalSeconds = AppSettings.instance.refreshIntervalSeconds;
    // Cleared up front so removing the last host retires the banner: with no
    // host every loader below returns early and none would ever clear it.
    _disconnected = false;
    setState(() {});
    _loadAppVersion();
    _loadVersionInfo();
    _loadSettings();
    _loadSbom();
    _loadDevices();
    _loadStorageDevices();
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
      return;
    }
    setState(() {
      _isLoadingRemoteAccess = true;
      _remoteAccessError = null;
    });
    try {
      final status = await RemoteAccessService.getStatus();
      if (!mounted) return;
      setState(() {
        _remoteAccessStatus = status;
        _isLoadingRemoteAccess = false;
      });
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

  Future<void> _enableRemoteAccess() async {
    setState(() => _isTogglingRemoteAccess = true);
    try {
      final status = await RemoteAccessService.enable();
      if (!mounted) return;
      setState(() {
        _remoteAccessStatus = status;
        _isTogglingRemoteAccess = false;
      });
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

  Future<void> _loadStorageDevices() async {
    if (AppSettings.instance.activeHost == null) {
      setState(() {
        _storageDevices = [];
        _storageError = null;
        _isLoadingStorage = false;
      });
      return;
    }
    setState(() {
      _isLoadingStorage = true;
      _storageError = null;
    });
    try {
      final devices = await StorageService.listDevices();
      if (!mounted) return;
      setState(() {
        _storageDevices = devices;
        _isLoadingStorage = false;
      });
      _noteReachability(null);
    } catch (e) {
      debugPrint('[settings_page.dart] Error loading storage devices: $e');
      if (!mounted) return;
      setState(() {
        _storageError = Errors.message(e, 'load your drives');
        _isLoadingStorage = false;
      });
      _noteReachability(e);
    }
  }

  Future<void> _mountDevice(StorageDevice device) async {
    try {
      await StorageService.mountDevice(device.serial);
      await _loadStorageDevices();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device mounted successfully')),
      );
    } catch (e) {
      debugPrint('[settings_page.dart] Error mounting device: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'mount the drive'))),
      );
    }
  }

  Future<void> _renameStorageDevice(StorageDevice device) async {
    final controller = TextEditingController(text: device.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Display name'),
          autofocus: true,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    if (newName == null || newName.isEmpty) return;
    try {
      await StorageService.renameDevice(device.devicePath, newName);
      await _loadStorageDevices();
    } catch (e) {
      debugPrint('[settings_page.dart] Error renaming storage device: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'rename the drive'))),
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
    return Scaffold(
      appBar: QuarkAppBar(
        label: 'Settings',
        icon: QuarkIcons.settings_outlined,
        actions: const [AppThemeToggle()],
      ),
      drawer: QuarkDrawer(
        activeSection: QuarkDrawerSection.settings,
        onTapFiles: () {
          context.go(AppRoutes.files);
        },
        onTapPhotos: () {
          context.go(AppRoutes.photos);
        },
        onTapTrash: () => context.go(AppRoutes.trash),
        onTapDocs: () {
          context.go(AppRoutes.docs);
        },
        onTapSheets: () {
          context.go(AppRoutes.sheets);
        },
        onTapDevices: () {
          context.go(AppRoutes.devices);
        },
        onTapHealth: () {
          context.go(AppRoutes.health);
        },
        onTapVault: () {
          context.go(AppRoutes.vault);
        },
        onTapSettings: () {
          Navigator.of(context).pop();
        },
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Above everything, because it explains every "Not connected" row
          // below it — and the address it points at is on this page (#1637).
          if (_disconnected) ...[
            QuarkDisconnectedBanner(onRetry: _load),
            const SizedBox(height: 24),
          ],
          const Text(
            'Quark',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (_appVersion != null)
            // Tapping the version is the whole affordance here: a button under
            // a one-line header would outweigh the line it annotates (#1756).
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: _appReleaseUrl == null
                    ? null
                    : () => _openReleaseNotes(_appReleaseUrl!),
                child: Text(
                  _appVersion!,
                  style: _appReleaseUrl == null
                      ? Theme.of(context).textTheme.bodySmall
                      : Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                          decorationColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                        ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Sign out — only show if there's an active session
          if (AppSettings.instance.sessionToken != null) ...[
            const Text(
              'Account',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(QuarkIcons.logout),
                title: const Text('Sign out'),
                onTap: _signOut,
              ),
            ),
            // Account deletion has to be initiated in the app and has to be
            // findable, per App Store Review Guideline 5.1.1(v). Directly
            // under Sign out, in the Account section, is where a person
            // looking for it looks (#1762).
            Card(
              child: ListTile(
                key: const ValueKey('settings_delete_account'),
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Delete account',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: const Text(
                  'Permanently deletes your account on this Quark',
                ),
                onTap: _accountActions.isWorking ? null : _deleteAccount,
              ),
            ),
            const SizedBox(height: 24),
            // The other intent, kept a section away from the first. Resetting
            // the appliance is not an account action and must never read like
            // one, so it gets its own heading and its own words rather than a
            // checkbox on the deletion dialog (#1762).
            const Text(
              'Reset',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                key: const ValueKey('settings_reset_quark'),
                leading: Icon(
                  Icons.restart_alt,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Reset this Quark',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: const Text(
                  'Erases every account and everything stored on this Quark, '
                  'returning it to setup',
                ),
                onTap: _accountActions.isWorking ? null : _resetQuark,
              ),
            ),
            const SizedBox(height: 24),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Installed version',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  if (AppSettings.instance.activeHost == null)
                    const Text(
                      'Not connected — add your Quark address under Backend hosts',
                    )
                  else if (_isLoadingVersionInfo)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (_versionLoadError != null)
                    Text(
                      _disconnected
                          ? quarkDisconnectedShort
                          : _versionLoadError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  else
                    Text(
                      _installedVersion ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (_installedReleaseUrl != null && !_isLoadingVersionInfo)
                    TextButton.icon(
                      onPressed: () => _openReleaseNotes(_installedReleaseUrl!),
                      icon: const Icon(QuarkIcons.open_in_new, size: 16),
                      label: const Text("What's in this release"),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_availableVersions.isEmpty &&
                      !_isLoadingVersionInfo &&
                      _versionLoadError == null &&
                      AppSettings.instance.activeHost != null)
                    const Text('No updates available')
                  else if (_availableVersions.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _selectedUpdateVersion,
                      items: _availableVersions
                          .map(
                            (v) => DropdownMenuItem<String>(
                              value: v,
                              child: Text(v),
                            ),
                          )
                          .toList(),
                      onChanged: (_isLoadingVersionInfo || _isUpdatingVersion)
                          ? null
                          : (v) {
                              setState(() {
                                _selectedUpdateVersion = v;
                              });
                            },
                      decoration: const InputDecoration(
                        labelText: 'Update Quark to version',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed:
                            (_selectedUpdateVersion == null ||
                                _isUpdatingVersion)
                            ? null
                            : _performUpdate,
                        icon: _isUpdatingVersion
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(QuarkIcons.update),
                        label: Text(
                          _isUpdatingVersion ? 'Updating...' : 'Start update',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (AppSettings.instance.activeHost != null)
            Card(
              child: _isLoadingAutoUpdate
                  ? const ListTile(
                      title: Text('Automatic updates'),
                      subtitle: Text(
                        'Quark will check for and install updates daily',
                      ),
                      trailing: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : SwitchListTile(
                      title: const Text('Automatic updates'),
                      subtitle: _autoUpdateError != null
                          ? Text(
                              _disconnected
                                  ? quarkDisconnectedShort
                                  : _autoUpdateError!,
                              style: const TextStyle(color: Colors.red),
                            )
                          : const Text(
                              'Quark will check for and install updates daily',
                            ),
                      value: _autoUpdate,
                      onChanged: _autoUpdateError != null
                          ? null
                          : (newValue) async {
                              setState(() {
                                _autoUpdate = newValue;
                              });
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                await SettingsService.setAutoUpdate(newValue);
                              } catch (e) {
                                debugPrint(
                                  '[settings_page.dart] Error saving auto-update: $e',
                                );
                                if (!mounted) return;
                                setState(() {
                                  _autoUpdate = !newValue;
                                });
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      Errors.message(e, 'save the setting'),
                                    ),
                                  ),
                                );
                              }
                            },
                    ),
            ),
          const SizedBox(height: 24),
          const Text(
            'Auto-refresh interval',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _refreshIntervalSeconds,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Disabled')),
              DropdownMenuItem(value: 10, child: Text('10 seconds')),
              DropdownMenuItem(value: 15, child: Text('15 seconds')),
              DropdownMenuItem(value: 30, child: Text('30 seconds')),
              DropdownMenuItem(value: 60, child: Text('1 minute')),
              DropdownMenuItem(value: 120, child: Text('2 minutes')),
              DropdownMenuItem(value: 300, child: Text('5 minutes')),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await AppSettings.instance.setRefreshIntervalSeconds(v);
              setState(() => _refreshIntervalSeconds = v);
            },
          ),
          if (AppSettings.instance.activeHost != null) ...[
            const SizedBox(height: 24),
            const Text(
              'Remote Access',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _isLoadingRemoteAccess
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _remoteAccessError != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _disconnected
                                ? quarkDisconnectedShort
                                : _remoteAccessError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _loadRemoteAccess,
                            icon: const Icon(QuarkIcons.refresh, size: 16),
                            label: const Text('Retry'),
                          ),
                        ],
                      )
                    : _remoteAccessStatus?.enabled == true
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                QuarkIcons.cloud_done_outlined,
                                size: 16,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Connected via Tailscale',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          if (_remoteAccessStatus?.remoteUrl != null &&
                              _remoteAccessStatus!.remoteUrl!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            CodeBlock(text: _remoteAccessStatus!.remoteUrl!),
                          ],
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _isTogglingRemoteAccess
                                ? null
                                : _disableRemoteAccess,
                            icon: _isTogglingRemoteAccess
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(QuarkIcons.link_off, size: 16),
                            label: const Text('Disable'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Access your quark from anywhere using Tailscale.',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _isTogglingRemoteAccess
                                ? null
                                : _enableRemoteAccess,
                            icon: _isTogglingRemoteAccess
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    QuarkIcons.vpn_key_outlined,
                                    size: 16,
                                  ),
                            label: const Text('Enable remote access'),
                          ),
                        ],
                      ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Theme',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          RadioGroup<ThemeMode>(
            groupValue: _theme,
            onChanged: (v) async {
              if (v == null) return;
              await AppSettings.instance.setThemeMode(v);
              setState(() {
                _theme = v;
              });
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: Text('System'),
                  value: ThemeMode.system,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Light'),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Dark'),
                  value: ThemeMode.dark,
                ),
              ],
            ),
          ),
          // Storage devices
          if (AppSettings.instance.activeHost != null) ...[
            const Text(
              'Storage',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: ExpansionTile(
                title: const Text(
                  'Storage devices',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _isLoadingStorage
                      ? 'Loading...'
                      : _storageError != null
                      ? Errors.loadFailedShort
                      : _storageDevices.isEmpty
                      ? 'No devices found'
                      : '${_storageDevices.length} device${_storageDevices.length == 1 ? '' : 's'}',
                ),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: RefreshIconButton(
                        isRefreshing: _isLoadingStorage,
                        onPressed: _loadStorageDevices,
                        tooltip: 'Refresh',
                      ),
                    ),
                  ),
                  if (_isLoadingStorage)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (_storageError != null)
                    ListTile(
                      leading: Icon(
                        QuarkIcons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        _disconnected ? quarkDisconnectedShort : _storageError!,
                      ),
                    )
                  else if (_storageDevices.isEmpty)
                    const ListTile(title: Text('No storage devices found'))
                  else
                    ..._storageDevices.map((device) {
                      return ListTile(
                        leading: Icon(
                          device.isInternal
                              ? QuarkIcons.storage_rounded
                              : device.isUnmounted
                              ? QuarkIcons.usb_off_rounded
                              : QuarkIcons.usb_rounded,
                        ),
                        title: Text(
                          device.name.isNotEmpty
                              ? device.name
                              : device.devicePath,
                        ),
                        subtitle: device.isUnmounted
                            ? const Text(
                                'Detected but not mounted',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                ),
                              )
                            : Text(
                                '${device.usedDisplay} · ${device.usedPercent.toStringAsFixed(1)}% used · ${device.fileSystem}',
                                style: const TextStyle(fontSize: 12),
                              ),
                        trailing: device.isUnmounted
                            ? FilledButton.tonalIcon(
                                icon: const Icon(QuarkIcons.play_arrow_rounded),
                                label: const Text('Mount'),
                                onPressed: device.serial.isNotEmpty
                                    ? () => _mountDevice(device)
                                    : null,
                              )
                            : IconButton(
                                icon: const Icon(QuarkIcons.edit_outlined),
                                tooltip: 'Rename',
                                onPressed: () => _renameStorageDevice(device),
                              ),
                      );
                    }),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Backend hosts',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          HostManager(onChanged: _load),
          const SizedBox(height: 24),
          const Text(
            'Connected Devices',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (AppSettings.instance.activeHost == null)
            const Text(
              'Not connected — add your Quark address under Backend hosts',
            )
          else
            Card(
              child: ExpansionTile(
                title: const Text(
                  'Client connections',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _isLoadingDevices
                      ? 'Loading...'
                      : _devicesError != null
                      ? Errors.loadFailedShort
                      : _connectedDevices.isEmpty
                      ? 'No devices recorded yet'
                      : '${_connectedDevices.length} device${_connectedDevices.length == 1 ? '' : 's'}',
                ),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: RefreshIconButton(
                        isRefreshing: _isLoadingDevices,
                        onPressed: _loadDevices,
                        tooltip: 'Refresh devices',
                      ),
                    ),
                  ),
                  if (_isLoadingDevices)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (_devicesError != null)
                    ListTile(
                      leading: Icon(
                        QuarkIcons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        _disconnected ? quarkDisconnectedShort : _devicesError!,
                      ),
                    )
                  else if (_connectedDevices.isEmpty)
                    const ListTile(title: Text('No devices recorded yet'))
                  else
                    ..._connectedDevices.map((device) {
                      return ListTile(
                        leading: const Icon(QuarkIcons.devices),
                        title: Text(device.ipAddress),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (device.userAgent.isNotEmpty)
                              Text(
                                device.userAgent,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            Text(
                              '${device.requestCount} request${device.requestCount == 1 ? '' : 's'} · last seen ${_formatRelative(device.lastSeenAt)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        isThreeLine: device.userAgent.isNotEmpty,
                        trailing: IconButton(
                          icon: const Icon(QuarkIcons.delete_outline),
                          tooltip: 'Remove',
                          onPressed: () => _deleteDevice(device.id),
                        ),
                      );
                    }),
                ],
              ),
            ),
          const SizedBox(height: 24),

          QuarkSection(
            title: 'Help & Support',
            icon: QuarkIcons.info_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const HelpSupportCard(),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: const Text('Terms of Service'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.terms),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          QuarkSection(
            title: 'Software Bill of Materials',
            icon: QuarkIcons.info_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isLoadingSbom)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else ...[
                  if (_sbomError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _sbomError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_flutterSbom != null)
                    SbomExpansionTile(
                      title: 'Flutter dependencies',
                      subtitle: '${_flutterSbom!.length} packages',
                      items: _flutterSbom!
                          .map(
                            (p) => SbomEntry(
                              name: p.name,
                              version: p.version,
                              url: p.url,
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 8),
                  if (_goSbom != null)
                    SbomExpansionTile(
                      title: 'Go dependencies',
                      subtitle:
                          '${_goSbom!.dependencies.length} packages · ${_goSbom!.goVersion}',
                      items: _goSbom!.dependencies
                          .map(
                            (d) => SbomEntry(name: d.path, version: d.version),
                          )
                          .toList(),
                    ),
                  if (_goSbom == null && _flutterSbom == null)
                    const Text('No SBOM data available.'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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

  /// Confirms deleting the account, then routes out.
  ///
  /// The controller does the deleting; the dialog and the navigation stay
  /// here, where a page's do.
  Future<void> _deleteAccount() async {
    final confirmUsername = await QuarkWidget.showDialog<String>(
      context,
      builder: (ctx) => DeleteAccountDialog(
        username: _accountActions.username,
        onConfirm: (typed) => Navigator.of(ctx).pop(typed),
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
    if (confirmUsername == null || !mounted) return;

    await _leaveAfter(
      () => _accountActions.deleteAccount(confirmUsername: confirmUsername),
      'Your account is gone.',
    );
  }

  /// Confirms a factory reset, then routes out.
  ///
  /// A separate entry, separate copy and separate call from [_deleteAccount]:
  /// nothing that starts as "delete my account" can end as a wiped appliance.
  Future<void> _resetQuark() async {
    final confirmation =
        await QuarkWidget.showDialog<(QuarkResetSelection, String)>(
          context,
          builder: (ctx) => ResetQuarkDialog(
            username: _accountActions.username,
            onConfirm: (selection, typed) =>
                Navigator.of(ctx).pop((selection, typed)),
            onCancel: () => Navigator.of(ctx).pop(),
          ),
        );
    if (confirmation == null || !mounted) return;

    await _leaveAfter(
      () => _accountActions.resetQuark(
        selection: confirmation.$1,
        confirmUsername: confirmation.$2,
      ),
      'This Quark has been reset.',
    );
  }

  /// Runs [action], then either reports why it failed or leaves the app for
  /// wherever a signed-out user belongs.
  ///
  /// [done] is what the user is told on the way out. The Quark reports whether
  /// files survived, so the notice about them is the truth after the fact
  /// rather than a second guess at what was asked for. The snack bar is shown
  /// before navigating on purpose: the root [ScaffoldMessenger] outlives this
  /// route, so the message survives the trip to setup or login.
  Future<void> _leaveAfter(
    Future<String?> Function() action,
    String done,
  ) async {
    setState(() {});
    final destination = await action();
    if (!mounted) return;
    setState(() {});

    final messenger = ScaffoldMessenger.of(context);
    if (destination == null) {
      messenger.showSnackBar(SnackBar(content: Text(_accountActions.error!)));
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _accountActions.filesRetained
              ? '$done Your files are still on this Quark.'
              : done,
        ),
      ),
    );
    // The token is already gone, so the router's gate would move the user on
    // regardless. Going straight there means they never watch this page fail
    // to load against a Quark they can no longer sign in to.
    context.go(destination);
  }

  @override
  void dispose() {
    _accountActions.dispose();
    super.dispose();
  }

  String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
