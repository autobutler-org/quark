// ---------------------------------------------------------------------------
// PluginRenderer
//
// A self-contained widget that interprets a declarative PluginNode tree and
// renders it as Flutter widgets. Designed to be extracted as a standalone
// library — has no imports from the rest of the app except the model.
//
// Supported node types:
//   centered    — Center with optional children
//   column      — Column with optional children
//   row         — Row with optional children
//   text        — Text widget; style: headline|title|body|caption
//   icon        — Material icon by name string; optional size
//   padding     — SizedBox / Padding; padding: all-sides shorthand
//   sized_box   — Empty sized box for spacing; size: height
//   button      — ElevatedButton; value: label, url: launch target
// ---------------------------------------------------------------------------

import 'package:autobutler/models/plugin_manifest.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders a [PluginNode] tree as Flutter widgets.
///
/// Usage:
/// ```dart
/// PluginRenderer(node: manifest.contributes.page!)
/// ```
class PluginRenderer extends StatelessWidget {
  const PluginRenderer({super.key, required this.node});

  final PluginNode node;

  @override
  Widget build(BuildContext context) => _render(context, node);

  // ---------------------------------------------------------------------------
  // Core interpreter
  // ---------------------------------------------------------------------------

  static Widget _render(BuildContext context, PluginNode node) {
    switch (node.type) {
      case 'centered':
        return Center(
          child: node.children.isEmpty
              ? const SizedBox.shrink()
              : node.children.length == 1
              ? _render(context, node.children.first)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: node.children
                      .map((c) => _render(context, c))
                      .toList(),
                ),
        );

      case 'column':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: node.children.map((c) => _render(context, c)).toList(),
        );

      case 'row':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: node.children.map((c) => _render(context, c)).toList(),
        );

      case 'text':
        return Text(
          node.value ?? '',
          style: _resolveTextStyle(context, node.style),
          textAlign: TextAlign.center,
        );

      case 'icon':
        return Icon(_resolveIcon(node.value ?? ''), size: node.size);

      case 'padding':
        final pad = node.padding ?? 8.0;
        return Padding(
          padding: EdgeInsets.all(pad),
          child: node.children.isNotEmpty
              ? _render(context, node.children.first)
              : const SizedBox.shrink(),
        );

      case 'sized_box':
        return SizedBox(height: node.size ?? 8.0);

      case 'button':
        return ElevatedButton(
          onPressed: node.url != null ? () => _launch(node.url!) : null,
          child: Text(node.value ?? 'Button'),
        );

      default:
        // Unknown type — render a subtle placeholder in debug, nothing in release.
        assert(false, 'PluginRenderer: unknown node type "${node.type}"');
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static TextStyle? _resolveTextStyle(BuildContext context, String? style) {
    final tt = Theme.of(context).textTheme;
    switch (style) {
      case 'headline':
        return tt.headlineMedium;
      case 'title':
        return tt.titleLarge;
      case 'caption':
        return tt.bodySmall;
      case 'body':
      default:
        return tt.bodyMedium;
    }
  }

  /// Resolves a Material icon by name string.
  /// Extend this map as needed. Falls back to [Icons.extension].
  static IconData _resolveIcon(String name) {
    const map = <String, IconData>{
      'waving_hand': Icons.waving_hand,
      'extension': Icons.extension,
      'download': Icons.download,
      'settings': Icons.settings,
      'folder': Icons.folder,
      'photo': Icons.photo,
      'health': Icons.monitor_heart_outlined,
      'home': Icons.home,
      'star': Icons.star,
      'info': Icons.info_outline,
      'check': Icons.check_circle_outline,
      'warning': Icons.warning_amber_outlined,
      'error': Icons.error_outline,
    };
    return map[name] ?? Icons.extension;
  }

  static Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ---------------------------------------------------------------------------
// Convenience wrapper: full Scaffold page for a plugin
// ---------------------------------------------------------------------------

/// A complete plugin page scaffold that renders the plugin's declared
/// [PluginNode] page tree, or a fallback message if none is defined.
class PluginPage extends StatelessWidget {
  const PluginPage({super.key, required this.name, this.pageNode});

  final String name;
  final PluginNode? pageNode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: pageNode != null
          ? PluginRenderer(node: pageNode!)
          : Center(child: Text('$name has no page defined.')),
    );
  }
}
