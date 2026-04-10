import 'package:autobutler/models/plugin_manifest.dart';
import 'package:flutter/foundation.dart';

/// Singleton that holds the currently loaded plugin list.
/// Pages read from this to populate the drawer without prop-drilling.
class PluginState extends ChangeNotifier {
  PluginState._();
  static final PluginState instance = PluginState._();

  List<PluginManifest> _plugins = const [];

  List<PluginManifest> get plugins => _plugins;

  void setPlugins(List<PluginManifest> plugins) {
    _plugins = plugins;
    notifyListeners();
  }
}
