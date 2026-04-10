import 'package:autobutler/router.dart';
import 'package:autobutler/services/app_settings.dart';
import 'package:autobutler/services/smb_service.dart';
import 'package:autobutler/services/auth_service.dart';
import 'package:autobutler/services/health_service.dart';
import 'package:autobutler/services/cirrus_service.dart';
import 'package:autobutler/services/connected_devices_service.dart';
import 'package:autobutler/services/sbom_service.dart';
import 'package:autobutler/services/settings_service.dart';
import 'package:autobutler/services/storage_service.dart';
import 'package:autobutler/utils/autobutler_widget.dart';
import 'package:autobutler/widgets/core/copy_button.dart';
import 'package:autobutler/widgets/layout/autobutler_app_bar.dart';
import 'package:autobutler/widgets/autobutler_drawer.dart';
import 'package:autobutler/widgets/refresh_icon_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<HostEntry> _hosts = [];
  int _active = -1;
  ThemeMode _theme = ThemeMode.system;
  String? _installedVersion;
  List<String> _availableVersions = [];
  String? _selectedUpdateVersion;
  bool _isLoadingVersionInfo = false;
  bool _isUpdatingVersion = false;
  String? _versionLoadError;

  bool _autoUpdate = false;
  bool _autoUpdateLoadFailed = false;
  bool _isLoadingAutoUpdate = false;

  // SBOM state
  GoSbom? _goSbom;
  List<FlutterPackage>? _flutterSbom;
  bool _isLoadingSbom = false;
  String? _sbomError;

  int _refreshIntervalSeconds = 15;

  // Connected devices state
  List<ConnectedDevice> _connectedDevices = [];
  bool _isLoadingDevices = false;
  String? _devicesError;

  // Storage devices state
  List<StorageDevice> _storageDevices = [];
  bool _isLoadingStorage = false;
  String? _storageError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _hosts = AppSettings.instance.hosts;
    _active = AppSettings.instance.activeIndex;
    _theme = AppSettings.instance.themeMode.value;
    _refreshIntervalSeconds = AppSettings.instance.refreshIntervalSeconds;
    setState(() {});
    _loadVersionInfo();
    _loadSettings();
    _loadSbom();
    _loadDevices();
    _loadStorageDevices();
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
    } catch (e) {
      debugPrint('[settings_page.dart] Error: $e');
      if (!mounted) return;
      setState(() {
        _devicesError = e.toString();
        _isLoadingDevices = false;
      });
    }
  }

  Future<void> _deleteDevice(int id) async {
    try {
      await ConnectedDevicesService.deleteDevice(id);
      await _loadDevices();
    } catch (e) {
      debugPrint('[settings_page.dart] Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove device: $e')));
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
    } catch (e) {
      debugPrint('[settings_page.dart] Error loading storage devices: $e');
      if (!mounted) return;
      setState(() {
        _storageError = e.toString();
        _isLoadingStorage = false;
      });
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to mount device: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to rename device: $e')));
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
      } catch (e) {
        debugPrint('[settings_page.dart] Error: $e');
        errors.add('Go SBOM: $e');
      }
    }

    try {
      nextFlutterSbom = await SbomService.getFlutterSbom();
    } catch (e) {
      debugPrint('[settings_page.dart] Error: $e');
      errors.add('Flutter SBOM: $e');
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
        _autoUpdateLoadFailed = false;
        _isLoadingAutoUpdate = false;
      });
    } catch (e) {
      debugPrint('[settings_page.dart] Error loading settings: $e');
      if (!mounted) return;
      setState(() {
        _autoUpdateLoadFailed = true;
        _isLoadingAutoUpdate = false;
      });
    }
  }

  Future<void> _loadVersionInfo() async {
    if (AppSettings.instance.activeHost == null) {
      setState(() {
        _installedVersion = null;
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
      final installed = await CirrusService.getInstalledVersion();
      final versions = await CirrusService.listAvailableVersions();
      if (!mounted) return;

      var installedVersion =
          (installed['semver'] as String?) ??
          (installed['version'] as String?) ??
          'Unknown';
      // When running an untagged dev build, show the short commit hash instead.
      if (installedVersion == 'NOSEMVER') {
        final commit = (installed['gitCommit'] as String?) ?? '';
        if (commit.isNotEmpty && commit != 'NOCOMMIT') {
          installedVersion = commit.substring(0, commit.length.clamp(0, 7));
        } else {
          installedVersion = 'dev (untagged)';
        }
      }
      final availableVersions = versions
          .map((m) => (m['version'] as String?) ?? '')
          .where((v) => v.isNotEmpty)
          .toList(growable: false);
      final selectedVersion = availableVersions.contains(_selectedUpdateVersion)
          ? _selectedUpdateVersion
          : (availableVersions.isNotEmpty ? availableVersions.first : null);

      setState(() {
        _installedVersion = installedVersion;
        _availableVersions = availableVersions;
        _selectedUpdateVersion = selectedVersion;
        _isLoadingVersionInfo = false;
      });
    } catch (e) {
      debugPrint('[settings_page.dart] Error: $e');
      if (!mounted) return;
      setState(() {
        _versionLoadError = e.toString();
        _isLoadingVersionInfo = false;
      });
    }
  }

  Future<void> _performUpdate() async {
    final version = _selectedUpdateVersion;
    if (version == null || _isUpdatingVersion) return;

    setState(() {
      _isUpdatingVersion = true;
    });

    try {
      await CirrusService.updateToVersion(version);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update started for $version')));
      await _loadVersionInfo();
    } catch (e) {
      debugPrint('[settings_page.dart] Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: ${e.toString()}')));
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingVersion = false;
        });
      }
    }
  }

  Future<void> _addOrEditHost({int? index}) async {
    final isEdit = index != null;
    final idx = index ?? 0;
    final nameController = TextEditingController(
      text: isEdit ? _hosts[idx].name : '',
    );
    final hostController = TextEditingController(
      text: isEdit ? _hosts[idx].hostAddress : '',
    );

    final result = await AutobutlerWidget.showDialog<bool>(
      context,
      builder: (context) => AutobutlerWidget.alertDialog(
        title: Text(isEdit ? 'Edit AutoButler' : 'Add AutoButler'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AutobutlerWidget.textField(
              controller: nameController,
              autofocus: true,
              hintText: 'Nickname (e.g. Home)',
            ),
            const SizedBox(height: 8),
            AutobutlerWidget.textField(
              controller: hostController,
              hintText: 'http://autobutler.home.local',
            ),
            const SizedBox(height: 6),
            const Text(
              'Usually http://autobutler.home.local or the IP address shown on your device.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final host = hostController.text.trim();
              if (name.isEmpty || host.isEmpty) return;
              final entry = HostEntry(name: name, hostAddress: host);
              final navigator = Navigator.of(context);
              if (isEdit) {
                await AppSettings.instance.updateHost(idx, entry);
              } else {
                await AppSettings.instance.addHost(entry);
              }
              navigator.pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      hostController.dispose();
    });

    if (result == true) {
      _load();
    }
  }

  Future<void> _removeHost(int index) async {
    final confirm = await AutobutlerWidget.showDialog(
      context,
      builder: (context) => AutobutlerWidget.alertDialog(
        title: const Text('Remove host'),
        content: const Text('Are you sure you want to remove this host?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AppSettings.instance.removeHost(index);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AutobutlerAppBar(
        label: 'Settings',
        icon: Icons.settings_outlined,
      ),
      drawer: AutobutlerDrawer(
        activeSection: AutobutlerDrawerSection.settings,
        onTapCirrus: () {
          context.go(AppRoutes.cirrus);
        },
        onTapPhotos: () {
          context.go(AppRoutes.photos);
        },
        onTapDevices: () {
          context.go(AppRoutes.devices);
        },
        onTapHealth: () {
          context.go(AppRoutes.health);
        },
        onTapSettings: () {
          Navigator.of(context).pop();
        },
        onTapPlugins: () {
          context.go(AppRoutes.plugins);
        },
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Autobutler',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: _signOut,
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
                      'Not connected — add your AutoButler address below',
                    )
                  else if (_isLoadingVersionInfo)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (_versionLoadError != null)
                    Text(
                      'Failed to load version info',
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
                        labelText: 'Update Autobutler to version',
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
                            : const Icon(Icons.update),
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
                        'AutoButler will check for and install updates daily',
                      ),
                      trailing: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : SwitchListTile(
                      title: const Text('Automatic updates'),
                      subtitle: _autoUpdateLoadFailed
                          ? const Text(
                              'Could not load setting — server may be unreachable',
                              style: TextStyle(color: Colors.red),
                            )
                          : const Text(
                              'AutoButler will check for and install updates daily',
                            ),
                      value: _autoUpdate,
                      onChanged: _autoUpdateLoadFailed
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
                                    content: Text('Failed to save setting: $e'),
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
                      ? 'Failed to load'
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
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: const Text('Failed to load storage devices'),
                      subtitle: Text(_storageError!),
                    )
                  else if (_storageDevices.isEmpty)
                    const ListTile(title: Text('No storage devices found'))
                  else
                    ..._storageDevices.map((device) {
                      return ListTile(
                        leading: Icon(
                          device.isInternal
                              ? Icons.storage_rounded
                              : device.isUnmounted
                              ? Icons.usb_off_rounded
                              : Icons.usb_rounded,
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
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Mount'),
                                onPressed: device.serial.isNotEmpty
                                    ? () => _mountDevice(device)
                                    : null,
                              )
                            : IconButton(
                                icon: const Icon(Icons.edit_outlined),
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
          RadioGroup<int>(
            groupValue: _active,
            onChanged: (v) async {
              if (v == null) return;
              await AppSettings.instance.setActiveIndex(v);
              _load();
            },
            child: Column(
              children: _hosts.asMap().entries.map((e) {
                final idx = e.key;
                final host = e.value;
                return Card(
                  child: ListTile(
                    leading: Radio<int>(value: idx),
                    title: Text(host.name),
                    subtitle: Text(host.hostAddress),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'edit') {
                          _addOrEditHost(index: idx);
                        } else if (action == 'remove') {
                          _removeHost(idx);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove'),
                        ),
                      ],
                    ),
                    onTap: () async {
                      await AppSettings.instance.setActiveIndex(idx);
                      _load();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _addOrEditHost(),
            icon: const Icon(Icons.add),
            label: const Text('Add AutoButler'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Connected Devices',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (AppSettings.instance.activeHost == null)
            const Text('Not connected — add your AutoButler address below')
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
                      ? 'Failed to load devices'
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
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: const Text('Failed to load devices'),
                      subtitle: Text(_devicesError!),
                    )
                  else if (_connectedDevices.isEmpty)
                    const ListTile(title: Text('No devices recorded yet'))
                  else
                    ..._connectedDevices.map((device) {
                      return ListTile(
                        leading: const Icon(Icons.devices),
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
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove',
                          onPressed: () => _deleteDevice(device.id),
                        ),
                      );
                    }),
                ],
              ),
            ),
          const SizedBox(height: 24),

          const _InfoSectionHeader(label: 'Network Drive'),
          const SizedBox(height: 8),
          _NetworkDriveCard(host: AppSettings.instance.activeHost),

          const SizedBox(height: 24),

          const _InfoSectionHeader(label: 'Software Bill of Materials'),
          const SizedBox(height: 8),
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
                  'Failed to load some SBOM sources:\n$_sbomError',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_flutterSbom != null)
              _SbomExpansionTile(
                title: 'Flutter dependencies',
                subtitle: '${_flutterSbom!.length} packages',
                items: _flutterSbom!
                    .map(
                      (p) => _SbomEntry(
                        name: p.name,
                        version: p.version,
                        url: p.url,
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 8),
            if (_goSbom != null)
              _SbomExpansionTile(
                title: 'Go dependencies',
                subtitle:
                    '${_goSbom!.dependencies.length} packages · ${_goSbom!.goVersion}',
                items: _goSbom!.dependencies
                    .map((d) => _SbomEntry(name: d.path, version: d.version))
                    .toList(),
              ),
            if (_goSbom == null && _flutterSbom == null)
              const Text('No SBOM data available.'),
          ],
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
    if (mounted) context.go(AppRoutes.cirrus);
  }

  String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _SbomEntry {
  const _SbomEntry({required this.name, required this.version, this.url});
  final String name;
  final String version;
  final String? url;
}

class _SbomExpansionTile extends StatelessWidget {
  const _SbomExpansionTile({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String title;
  final String subtitle;
  final List<_SbomEntry> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        children: items
            .map(
              (item) => ListTile(
                dense: true,
                title: Text(item.name, style: const TextStyle(fontSize: 13)),
                trailing: Text(
                  item.version,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Section header for read-only informational sections.
/// Uses a subtler visual treatment than action-oriented sections to signal
/// that the content is reference material, not something the user configures.
class _InfoSectionHeader extends StatelessWidget {
  const _InfoSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

/// Shows instructions for mounting AutoButler as a network drive.
/// Fetches the butler's hostname from the health endpoint so the paths
/// reflect the device's actual LAN name rather than the connection URL.
class _NetworkDriveCard extends StatefulWidget {
  const _NetworkDriveCard({required this.host});

  final String? host;

  @override
  State<_NetworkDriveCard> createState() => _NetworkDriveCardState();
}

class _NetworkDriveCardState extends State<_NetworkDriveCard> {
  String? _hostname;
  SmbStatus? _smbStatus;
  bool _smbLoading = false;
  bool _smbBusy = false;

  @override
  void initState() {
    super.initState();
    _fetchHostname();
    _loadSmbStatus();
  }

  Future<void> _loadSmbStatus() async {
    if (AppSettings.instance.activeHost == null) return;
    setState(() => _smbLoading = true);
    try {
      final status = await SmbService.getStatus();
      if (mounted) setState(() => _smbStatus = status);
    } catch (_) {
      debugPrint('[settings_page.dart] Failed to load SMB status');
    } finally {
      if (mounted) setState(() => _smbLoading = false);
    }
  }

  Future<void> _setupSmb(String user, String password) async {
    setState(() => _smbBusy = true);
    try {
      final status = await SmbService.setup(user, password);
      if (!mounted) return;
      setState(() => _smbStatus = status);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network drive set up successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Setup failed: $e')));
    } finally {
      if (mounted) setState(() => _smbBusy = false);
    }
  }

  Future<void> _showSmbSetupDialog({required bool refresh}) async {
    final userController = TextEditingController();
    final passController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          refresh ? 'Refresh network drive config' : 'Set up network drive',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the Linux username and password for Samba access.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: userController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Set up'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      userController.dispose();
      passController.dispose();
    });
    if (result != true || !mounted) return;
    await _setupSmb(userController.text.trim(), passController.text);
  }

  Future<void> _teardownSmb() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disable network drive'),
        content: const Text(
          'This will stop the Samba service and remove the share. '
          'Connected clients will lose access. Continue?',
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
    setState(() => _smbBusy = true);
    try {
      final status = await SmbService.teardown();
      if (!mounted) return;
      setState(() => _smbStatus = status);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network drive disabled')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to disable: $e')));
    } finally {
      if (mounted) setState(() => _smbBusy = false);
    }
  }

  Future<void> _fetchHostname() async {
    if (AppSettings.instance.activeHost == null) return;
    try {
      final status = await HealthService.getHealth();
      if (mounted && status.hostname.isNotEmpty) {
        setState(() => _hostname = status.hostname);
      }
    } catch (_) {
      // Fall back to extracting from URL — better than nothing.
    }
  }

  String get _displayHostname {
    String raw;
    if (_hostname != null && _hostname!.isNotEmpty) {
      raw = _hostname!;
    } else {
      final h = widget.host;
      if (h == null) return 'autobutler.local';
      final uri = Uri.tryParse(h);
      raw = uri?.host ?? h;
    }
    // Strip .local suffix — the card appends it, so avoid doubling.
    if (raw.endsWith('.local')) {
      return raw.substring(0, raw.length - '.local'.length);
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final hostname = _displayHostname;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mount as network drive',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Access your AutoButler files directly from your operating system\'s file browser.',
            ),
            const SizedBox(height: 16),

            // SMB setup controls (Linux only)
            if (AppSettings.instance.activeHost != null) ...[
              if (_smbLoading)
                const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_smbStatus != null && _smbStatus!.linux) ...[
                if (_smbStatus!.configured) ...[
                  Row(
                    children: [
                      Icon(
                        _smbStatus!.running
                            ? Icons.check_circle_outline
                            : Icons.warning_amber,
                        size: 16,
                        color: _smbStatus!.running
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _smbStatus!.running
                            ? 'Network drive active'
                            : 'Network drive configured but not running',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _smbBusy
                            ? null
                            : () async {
                                await _showSmbSetupDialog(refresh: true);
                              },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Refresh config'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _smbBusy ? null : _teardownSmb,
                        icon: const Icon(Icons.link_off, size: 16),
                        label: const Text('Disable'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  OutlinedButton.icon(
                    onPressed: _smbBusy
                        ? null
                        : () => _showSmbSetupDialog(refresh: false),
                    icon: _smbBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_link, size: 16),
                    label: const Text('Set up network drive'),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
              ],
            ],

            ..._buildMountInstructions(hostname),
          ],
        ),
      ),
    );
  }

  /// Returns mount instructions for the current platform only.
  /// On mobile (iOS/Android), shows nothing (no mount support).
  /// On desktop/web, shows the relevant OS section.
  List<Widget> _buildMountInstructions(String hostname) {
    final platform = defaultTargetPlatform;
    final isMobile =
        platform == TargetPlatform.iOS || platform == TargetPlatform.android;

    final widgets = <Widget>[];

    if (!isMobile) {
      switch (platform) {
        case TargetPlatform.macOS:
          widgets.addAll([
            const Text('macOS', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            _CodeBlock(text: 'smb://$hostname.local'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse('smb://$hostname.local')),
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('Open in Finder'),
            ),
          ]);
        case TargetPlatform.windows:
          widgets.addAll([
            const Text(
              'Windows',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            _CodeBlock(text: '\\\\$hostname.local'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('file://$hostname.local/'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('Open in File Explorer'),
            ),
          ]);
        case TargetPlatform.linux:
          widgets.addAll([
            const Text('Linux', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            _CodeBlock(text: 'smb://$hostname.local'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse('smb://$hostname.local')),
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('Open in Files'),
            ),
          ]);
        default:
          break;
      }

      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 12));
      }
    }

    return widgets;
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          CopyButton(text: text),
        ],
      ),
    );
  }
}
