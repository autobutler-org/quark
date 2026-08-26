import 'package:flutter/foundation.dart';
import 'package:quark/models/plugin_manifest.dart';

/// The installed plugins, shared by the drawer, which lists them, and the
/// plugin page, which renders one. [PluginService.refresh] fills it.
class PluginState extends ChangeNotifier {
  PluginState._();

  /// The shared instance.
  static final PluginState instance = PluginState._();

  List<PluginManifest> _plugins = const [];

  /// Every installed, enabled plugin.
  List<PluginManifest> get plugins => _plugins;

  /// Replaces the list and tells the listeners.
  void setPlugins(List<PluginManifest> plugins) {
    _plugins = plugins;
    notifyListeners();
  }
}
