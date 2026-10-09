import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// Calls `/api/v0/settings` for the Quark's settings, such as automatic updates
/// and the theme color (#2740).
class SettingsService with AuthenticatedService {
  static final SettingsService _instance = SettingsService._();
  SettingsService._();
  static SettingsService get instance => _instance;

  static Future<bool> getAutoUpdate() async {
    final uri = apiBaseUri.resolve('/api/v0/settings');
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to fetch settings');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid settings response format');
    }
    final data = decoded['data'];
    final map = data is Map<String, dynamic> ? data : decoded;
    return map['autoUpdate'] as bool? ?? false;
  }

  static Future<void> setAutoUpdate(bool enabled) async {
    final uri = apiBaseUri.resolve('/api/v0/settings');
    final body = jsonEncode({'autoUpdate': enabled});
    final response = await instance.authenticatedPost(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to update settings');
    }
  }

  /// The Quark's default theme color as its storage string, empty when its admin
  /// has not chosen one. `GET /settings/public` needs no session, so the
  /// sign-in page can ask.
  static Future<String> getQuarkThemeColor() async {
    final response = await instance.httpClient.get(
      apiBaseUri.resolve('/api/v0/settings/public'),
    );
    return _themeColorOf(
      _readSettings(response, 'Failed to fetch public settings'),
    );
  }

  /// Sets the Quark's default theme color to the storage string [themeColor]; empty
  /// clears it. Admin-only.
  static Future<void> setQuarkThemeColor(String themeColor) async {
    final response = await instance.authenticatedPut(
      apiBaseUri.resolve('/api/v0/settings/theme-color'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'themeColor': themeColor}),
    );
    _readSettings(response, 'Failed to save the theme color');
  }

  /// The signed-in user's own theme color as its storage string, empty when they
  /// follow the Quark's.
  static Future<String> getMyThemeColor() async =>
      _themeColorOf(await getMySettings());

  /// Sets the signed-in user's own theme color to the storage string [themeColor];
  /// empty follows the Quark's. Every other setting is kept, see
  /// [updateMySettings].
  static Future<void> setMyThemeColor(String themeColor) =>
      updateMySettings((current) => {...current, 'themeColor': themeColor});

  /// The signed-in user's own settings as the Quark holds them: `themeColor`,
  /// `disabledNotifications` (left out when every type is on), and whatever
  /// a newer Quark adds.
  static Future<Map<String, dynamic>> getMySettings() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve(_mySettingsPath),
    );
    return _readSettings(response, 'Failed to fetch your settings');
  }

  /// Saves the signed-in user's own settings as [change] makes them from the
  /// current ones, and returns what the Quark saved.
  ///
  /// `PUT /settings/me` replaces the settings whole, so every write of one
  /// field goes through here: it reads first and sends the rest back
  /// unchanged. A theme color save that sent only the color would turn every
  /// notification type back on (#2493).
  static Future<Map<String, dynamic>> updateMySettings(
    Map<String, dynamic> Function(Map<String, dynamic> current) change,
  ) async {
    final settings = change(await getMySettings());
    final response = await instance.authenticatedPut(
      apiBaseUri.resolve(_mySettingsPath),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(settings),
    );
    return _readSettings(response, 'Failed to save your settings');
  }

  static const _mySettingsPath = '/api/v0/settings/me';

  static String _themeColorOf(Map<String, dynamic> settings) =>
      settings['themeColor'] is String ? settings['themeColor'] as String : '';

  /// The settings object in [response], empty when the body is not one.
  /// Throws an [ApiException] carrying [context] for a non-success status.
  static Map<String, dynamic> _readSettings(
    http.Response response,
    String context,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, context);
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  /// Fetches the active Quark's default theme color and, with a session, the
  /// user's own into [AppSettings], which resolves the two into the theme.
  ///
  /// Never throws: a failed call keeps what is known, so the app stays on
  /// the cached theme color and signing in is never held up by a color. An answer
  /// that arrives after the host or the session changed is dropped.
  static Future<void> refreshThemeColor() async {
    final settings = AppSettings.instance;
    final host = settings.activeHost;
    final token = settings.sessionToken;
    if (host == null) return;
    if (token == null) await settings.setUserThemeColor(null);

    Future<void> load(
      Future<String> Function() fetch,
      Future<void> Function(String?) apply,
    ) async {
      try {
        final themeColor = await fetch();
        if (settings.activeHost == host && settings.sessionToken == token) {
          await apply(themeColor);
        }
      } catch (e) {
        debugPrint('[settings_service.dart] refreshThemeColor failed: $e');
      }
    }

    await Future.wait([
      load(getQuarkThemeColor, settings.setQuarkThemeColor),
      if (token != null) load(getMyThemeColor, settings.setUserThemeColor),
    ]);
  }
}
