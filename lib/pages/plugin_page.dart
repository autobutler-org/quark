import 'package:flutter/material.dart';
import 'package:quark/services/plugin_state.dart';
import 'package:quark/utils/plugin_icons.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/plugin_renderer.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One installed plugin's page, `/plugins/<id>`: the page tree its manifest
/// declares, drawn by [PluginRenderer].
///
/// It follows [PluginState], so a page opened by its link fills in once the
/// installed plugins have loaded, and empties when the plugin is uninstalled.
class PluginPage extends StatelessWidget {
  /// Creates the page of the plugin [pluginId].
  const PluginPage({required this.pluginId, super.key});

  /// The id of the plugin to show.
  final String pluginId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PluginState.instance,
      builder: (context, _) {
        final plugin = PluginState.instance.plugins
            .where((p) => p.id == pluginId)
            .firstOrNull;
        final page = plugin?.contributes.page;
        return QuarkPageScaffold(
          title: plugin?.name ?? 'Plugin',
          icon: plugin?.contributes.navItem == null
              ? QuarkIcons.extension_outlined
              : pluginIcon(plugin!.contributes.navItem!.icon),
          drawer: AppDrawer(
            activeSection: QuarkDrawerSection.plugins,
            activePluginId: pluginId,
          ),
          body: page != null
              ? PluginRenderer(node: page)
              : Center(
                  child: Text(
                    plugin == null
                        ? 'This plugin is not installed.'
                        : '${plugin.name} has no page defined.',
                  ),
                ),
        );
      },
    );
  }
}
