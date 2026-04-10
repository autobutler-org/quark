import 'dart:convert';

import 'package:autobutler/models/plugin_manifest.dart';
import 'package:autobutler/services/app_settings.dart';
import 'package:autobutler/services/authenticated_service.dart';
import 'package:http/http.dart' as http;

class PluginService with AuthenticatedService {
  static final PluginService _instance = PluginService._();
  PluginService._();

  static Map<String, String> get _authHeaders => _instance.authHeaders;

  static Uri get _apiBaseUri {
    final base = AppSettings.instance.activeHost ?? 'http://localhost:8080';
    return Uri.parse(base);
  }

  /// Fetches the list of installed, enabled plugins from the backend.
  static Future<List<PluginManifest>> listPlugins() async {
    final uri = _apiBaseUri.resolve('/api/v1/plugins');
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
}
