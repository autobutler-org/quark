import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quark/models/plugin_manifest.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/plugin_state.dart';
import 'package:quark/utils/error_text.dart';

/// The plugins API, `/api/v0/plugins`: the installed plugins, the marketplace,
/// and installing and uninstalling one.
class PluginService with AuthenticatedService {
  PluginService._();

  /// The shared instance, which carries the session.
  static final PluginService instance = PluginService._();

  static List<Map<String, dynamic>> _list(String body) {
    final decoded = jsonDecode(body);
    final list = decoded is List ? decoded : (decoded['data'] as List? ?? []);
    return list.cast<Map<String, dynamic>>();
  }

  /// Returns all installed, enabled plugins.
  static Future<List<PluginManifest>> listPlugins() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/plugins'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to list plugins');
    }
    return _list(response.body)
        .map(PluginManifest.fromJson)
        .where((p) => p.enabled)
        .toList(growable: false);
  }

  /// Returns all marketplace plugins, each annotated with whether it is
  /// installed.
  static Future<List<MarketplaceEntry>> listMarketplace() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/plugins/marketplace'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to list marketplace');
    }
    return _list(
      response.body,
    ).map(MarketplaceEntry.fromJson).toList(growable: false);
  }

  /// Installs a plugin by ID.
  static Future<void> installPlugin(String id) async {
    final response = await instance.authenticatedPost(
      apiBaseUri.resolve('/api/v0/plugins/${Uri.encodeComponent(id)}/install'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to install plugin $id');
    }
  }

  /// Uninstalls a plugin by ID.
  static Future<void> uninstallPlugin(String id) async {
    final response = await instance.authenticatedDelete(
      apiBaseUri.resolve('/api/v0/plugins/${Uri.encodeComponent(id)}'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to uninstall plugin $id');
    }
  }

  /// Fetches the installed plugins into [PluginState], so the drawer and the
  /// plugin pages follow them. Without a session there are none; a failed
  /// call keeps the last known list, since plugins are not critical.
  static Future<void> refresh() async {
    if (AppSettings.instance.sessionToken == null) {
      PluginState.instance.setPlugins(const []);
      return;
    }
    try {
      PluginState.instance.setPlugins(await listPlugins());
    } catch (e) {
      debugPrint('[plugin_service.dart] refresh failed: $e');
    }
  }
}
