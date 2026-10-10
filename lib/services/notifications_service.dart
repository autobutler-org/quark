import 'dart:convert';

import 'package:quark/models/app_notification.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/settings_service.dart';
import 'package:quark/utils/error_text.dart';

/// Calls `GET /api/v0/notifications` for the account's current notifications,
/// and reads and writes which types the account turned off, which live in its
/// own settings (`/api/v0/settings/me`, through [SettingsService]).
class NotificationsService with AuthenticatedService {
  static final NotificationsService _instance = NotificationsService._();
  NotificationsService._();
  static NotificationsService get instance => _instance;

  static const _disabledKey = 'disabledNotifications';

  /// The account's current notifications. An entry of a type this app does
  /// not know is left out.
  static Future<List<AppNotification>> list() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/notifications'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to list notifications');
    }
    final decoded = jsonDecode(response.body);
    final entries = decoded is Map ? decoded['notifications'] : null;
    if (entries is! List) {
      throw const FormatException('Invalid notifications response format');
    }
    return [for (final entry in entries) ?AppNotification.tryFromJson(entry)];
  }

  /// The types the account turned off, as the API spells them. Kept as
  /// strings so a type this app does not know survives a save.
  static Future<Set<String>> disabledTypes() async =>
      _disabledIn(await SettingsService.getMySettings());

  /// Turns [type] on or off for the account and returns the types that are
  /// off afterwards. Every other setting, and every other type, is kept.
  static Future<Set<String>> setEnabled(
    NotificationType type,
    bool enabled,
  ) async {
    final saved = await SettingsService.updateMySettings((current) {
      final disabled = _disabledIn(current);
      enabled ? disabled.remove(type.wire) : disabled.add(type.wire);
      return {...current, _disabledKey: disabled.toList()};
    });
    return _disabledIn(saved);
  }

  static Set<String> _disabledIn(Map<String, dynamic> settings) {
    final disabled = settings[_disabledKey];
    return disabled is List ? disabled.whereType<String>().toSet() : {};
  }
}
