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

  const PluginContributes({this.navItem, this.settingsPanel = false});

  factory PluginContributes.fromJson(Map<String, dynamic> json) =>
      PluginContributes(
        navItem: json['navItem'] != null
            ? PluginNavItem.fromJson(json['navItem'] as Map<String, dynamic>)
            : null,
        settingsPanel: json['settingsPanel'] as bool? ?? false,
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
