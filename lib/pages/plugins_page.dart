import 'package:autobutler/models/plugin_manifest.dart';
import 'package:autobutler/router.dart';
import 'package:autobutler/services/plugin_service.dart';
import 'package:autobutler/services/plugin_state.dart';
import 'package:autobutler/widgets/autobutler_drawer.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  List<MarketplaceEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _inProgress = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await PluginService.listMarketplace();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _install(MarketplaceEntry entry) async {
    setState(() => _inProgress.add(entry.id));
    try {
      await PluginService.installPlugin(entry.id);
      // Refresh the installed plugin list so the router + drawer update.
      final plugins = await PluginService.listPlugins();
      if (!mounted) return;
      PluginState.instance.setPlugins(plugins);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${entry.name} installed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to install ${entry.name}: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _inProgress.remove(entry.id));
    }
  }

  Future<void> _uninstall(MarketplaceEntry entry) async {
    setState(() => _inProgress.add(entry.id));
    try {
      await PluginService.uninstallPlugin(entry.id);
      final plugins = await PluginService.listPlugins();
      if (!mounted) return;
      PluginState.instance.setPlugins(plugins);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${entry.name} uninstalled')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to uninstall ${entry.name}: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _inProgress.remove(entry.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugins'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      drawer: ListenableBuilder(
        listenable: PluginState.instance,
        builder: (context, _) => AutobutlerDrawer(
          activeSection: AutobutlerDrawerSection.plugins,
          plugins: PluginState.instance.plugins,
          onTapCirrus: () => context.go(AppRoutes.cirrus),
          onTapPhotos: () => context.go(AppRoutes.photos),
          onTapDevices: () => context.go(AppRoutes.devices),
          onTapHealth: () => context.go(AppRoutes.health),
          onTapSettings: () => context.go(AppRoutes.settings),
          onTapPlugins: () => Navigator.of(context).pop(),
          onTapPlugin: (plugin) => context.go(AppRoutes.pluginPath(plugin.id)),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('No plugins available.'));
    }

    final installed = _entries.where((e) => e.installed).toList();
    final available = _entries.where((e) => !e.installed).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (installed.isNotEmpty) ...[
          _sectionHeader('Installed'),
          ...installed.map((e) => _pluginCard(e)),
          const SizedBox(height: 24),
        ],
        if (available.isNotEmpty) ...[
          _sectionHeader('Available'),
          ...available.map((e) => _pluginCard(e)),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget _pluginCard(MarketplaceEntry entry) {
    final busy = _inProgress.contains(entry.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          child: Icon(
            AutobutlerDrawer.iconFromName(
              entry.contributes.navItem?.icon ?? 'extension',
            ),
          ),
        ),
        title: Text(
          entry.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.description),
            const SizedBox(height: 4),
            Text(
              'v${entry.version} · by ${entry.author}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : entry.installed
            ? OutlinedButton(
                onPressed: () => _uninstall(entry),
                child: const Text('Uninstall'),
              )
            : FilledButton(
                onPressed: () => _install(entry),
                child: const Text('Install'),
              ),
      ),
    );
  }
}
