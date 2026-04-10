import 'dart:convert';

import 'package:autobutler/models/plugin_manifest.dart';
import 'package:autobutler/services/app_settings.dart';
import 'package:autobutler/services/authenticated_service.dart';
import 'package:http/http.dart' as http;

class PluginService with AuthenticatedService {
  static final PluginService _instance = PluginService._();
  PluginService._();

  static Map<String, String> get _authHeaders => _instance.authHeaders;

  static Uri get _base {
    final base = AppSettings.instance.activeHost ?? 'http://localhost:8080';
    return Uri.parse(base);
  }

  /// Returns all installed, enabled plugins.
  static Future<List<PluginManifest>> listPlugins() async {
    final uri = _base.resolve('/api/v1/plugins');
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to list plugins (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    final list = decoded is List ? decoded : (decoded['data'] as List? ?? []);
    return list
        .cast<Map<String, dynamic>>()
        .map(PluginManifest.fromJson)
        .where((p) => p.enabled)
        .toList(growable: false);
  }

  /// Returns all marketplace plugins, each annotated with [installed] status.
  static Future<List<MarketplaceEntry>> listMarketplace() async {
    final uri = _base.resolve('/api/v1/plugins/marketplace');
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to list marketplace (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    final list = decoded is List ? decoded : (decoded['data'] as List? ?? []);
    return list
        .cast<Map<String, dynamic>>()
        .map(MarketplaceEntry.fromJson)
        .toList(growable: false);
  }

  /// Installs a plugin by ID.
  static Future<void> installPlugin(String id) async {
    final uri = _base.resolve('/api/v1/plugins/$id/install');
    final response = await http.post(uri, headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to install plugin $id (${response.statusCode})');
    }
  }

  /// Uninstalls a plugin by ID.
  static Future<void> uninstallPlugin(String id) async {
    final uri = _base.resolve('/api/v1/plugins/$id');
    final response = await http.delete(uri, headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to uninstall plugin $id (${response.statusCode})',
      );
    }
  }
}
