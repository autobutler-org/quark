import 'package:flutter/material.dart';
import 'package:quark/models/plugin_manifest.dart';
import 'package:quark/services/plugin_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/plugin_icons.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The plugin marketplace: every plugin the Quark offers, the installed ones
/// first, each with a button to install or uninstall it.
class PluginsPage extends StatefulWidget {
  /// Creates the marketplace page.
  const PluginsPage({super.key});

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  List<MarketplaceEntry> _entries = const [];
  String? _error;
  final Set<String> _inProgress = {};

  @override
  Future<void> refresh() async {
    try {
      final entries = await PluginService.listMarketplace();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = Errors.message(e, 'load the plugins'));
    }
  }

  /// Installs or uninstalls [entry], whichever it is not, then reloads the
  /// installed plugins so the drawer follows, and the marketplace.
  Future<void> _toggle(MarketplaceEntry entry) async {
    final install = !entry.installed;
    setState(() => _inProgress.add(entry.id));
    try {
      await (install
          ? PluginService.installPlugin(entry.id)
          : PluginService.uninstallPlugin(entry.id));
      await PluginService.refresh();
      await manualRefresh();
      _showMessage('${entry.name} ${install ? 'installed' : 'uninstalled'}');
    } catch (e) {
      _showMessage(
        Errors.message(e, '${install ? 'install' : 'uninstall'} ${entry.name}'),
      );
    } finally {
      if (mounted) setState(() => _inProgress.remove(entry.id));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return QuarkPageScaffold(
      title: 'Plugins',
      icon: QuarkIcons.extension_outlined,
      onRefresh: manualRefresh,
      isRefreshing: isRefreshing,
      drawer: const AppDrawer(activeSection: QuarkDrawerSection.plugins),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isInitialLoad) {
      return const Center(child: QuarkLoader());
    }
    if (_error != null && _entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: manualRefresh,
              child: const Text('Retry'),
            ),
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
          ...installed.map(_pluginCard),
          const SizedBox(height: 24),
        ],
        if (available.isNotEmpty) ...[
          _sectionHeader('Available'),
          ...available.map(_pluginCard),
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
            pluginIcon(entry.contributes.navItem?.icon ?? 'extension'),
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
            ? const QuarkLoader(size: 24)
            : entry.installed
            ? OutlinedButton(
                key: ValueKey('plugin_uninstall_${entry.id}'),
                onPressed: () => _toggle(entry),
                child: const Text('Uninstall'),
              )
            : FilledButton(
                key: ValueKey('plugin_install_${entry.id}'),
                onPressed: () => _toggle(entry),
                child: const Text('Install'),
              ),
      ),
    );
  }
}
