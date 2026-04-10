import 'package:autobutler/pages/plugins/hello_plugin_page.dart';
import 'package:flutter/material.dart';

/// Maps plugin IDs to their native Flutter page builders.
/// Add entries here when shipping new first-party native plugins.
final Map<String, WidgetBuilder> pluginPageRegistry = {
  'hello': (_) => const HelloPluginPage(),
};
