// ---------------------------------------------------------------------------
// Plugin manifest model
// ---------------------------------------------------------------------------

/// A single node in the declarative widget tree.
///
/// The [type] field determines rendering. Supported types:
///   centered, column, row, text, icon, padding, sized_box, button
class PluginNode {
  final String type;

  /// Text content (type=text) or Material icon name (type=icon, type=button).
  final String? value;

  /// Text style hint: headline | title | body | caption
  final String? style;

  /// Icon size (type=icon) or sized_box dimension.
  final double? size;

  /// URL to launch on tap (type=button).
  final String? url;

  /// All-sides padding shorthand (type=padding).
  final double? padding;

  final List<PluginNode> children;

  /// Open-ended extension bag for future attrs.
  final Map<String, String> attrs;

  const PluginNode({
    required this.type,
    this.value,
    this.style,
    this.size,
    this.url,
    this.padding,
    this.children = const [],
    this.attrs = const {},
  });

  factory PluginNode.fromJson(Map<String, dynamic> json) => PluginNode(
    type: json['type'] as String? ?? 'text',
    value: json['value'] as String?,
    style: json['style'] as String?,
    size: (json['size'] as num?)?.toDouble(),
    url: json['url'] as String?,
    padding: (json['padding'] as num?)?.toDouble(),
    children:
        (json['children'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>()
            .map(PluginNode.fromJson)
            .toList(growable: false) ??
        const [],
    attrs:
        (json['attrs'] as Map<String, dynamic>?)?.cast<String, String>() ??
        const {},
  );
}

// ---------------------------------------------------------------------------

class PluginNavItem {
  final String label;
  final String icon;
  final String route;

  const PluginNavItem({
    required this.label,
    required this.icon,
    required this.route,
  });

  factory PluginNavItem.fromJson(Map<String, dynamic> json) => PluginNavItem(
    label: json['label'] as String? ?? '',
    icon: json['icon'] as String? ?? 'extension',
    route: json['route'] as String? ?? '',
  );
}

class PluginContributes {
  final PluginNavItem? navItem;
  final bool settingsPanel;

  /// Declarative widget tree for the plugin page.
  /// When present, the frontend renders this instead of a hardcoded page.
  final PluginNode? page;

  const PluginContributes({
    this.navItem,
    this.settingsPanel = false,
    this.page,
  });

  factory PluginContributes.fromJson(Map<String, dynamic> json) =>
      PluginContributes(
        navItem: json['navItem'] != null
            ? PluginNavItem.fromJson(json['navItem'] as Map<String, dynamic>)
            : null,
        settingsPanel: json['settingsPanel'] as bool? ?? false,
        page: json['page'] != null
            ? PluginNode.fromJson(json['page'] as Map<String, dynamic>)
            : null,
      );
}

class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final bool enabled;
  final PluginContributes contributes;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.enabled,
    required this.contributes,
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) => PluginManifest(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    version: json['version'] as String? ?? '',
    description: json['description'] as String? ?? '',
    author: json['author'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? false,
    contributes: json['contributes'] != null
        ? PluginContributes.fromJson(
            json['contributes'] as Map<String, dynamic>,
          )
        : const PluginContributes(),
  );
}

// ---------------------------------------------------------------------------

/// A plugin from the marketplace, annotated with whether it is installed.
class MarketplaceEntry extends PluginManifest {
  final bool installed;

  const MarketplaceEntry({
    required super.id,
    required super.name,
    required super.version,
    required super.description,
    required super.author,
    required super.enabled,
    required super.contributes,
    required this.installed,
  });

  factory MarketplaceEntry.fromJson(Map<String, dynamic> json) =>
      MarketplaceEntry(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        version: json['version'] as String? ?? '',
        description: json['description'] as String? ?? '',
        author: json['author'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? false,
        contributes: json['contributes'] != null
            ? PluginContributes.fromJson(
                json['contributes'] as Map<String, dynamic>,
              )
            : const PluginContributes(),
        installed: json['installed'] as bool? ?? false,
      );
}
