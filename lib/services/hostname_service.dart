import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/hostname_status.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The admin-only device name API: `/api/v0/hostname` (#2344).
///
/// A 4xx carries the Quark's own hand-written sentence ("this Quark can't be
/// renamed"), so it goes through [throwApiError]. A 5xx carries the rename
/// helper's output, which is a diagnostic, so it becomes a bare
/// [ApiException].
class HostnameService with AuthenticatedService {
  HostnameService._();
  static final HostnameService instance = HostnameService._();

  /// What the Quark is called and whether it can be renamed.
  static Future<HostnameStatus> getStatus() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/hostname'),
    );
    return _read(response, 'load the device name');
  }

  /// Renames the Quark to [hostname], with no reboot. The answer names what
  /// the device ended up advertising, which is another name when a device on
  /// the network already had this one.
  static Future<HostnameStatus> setHostname(String hostname) async {
    final response = await instance.authenticatedPut(
      apiBaseUri.resolve('/api/v0/hostname'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'hostname': hostname}),
    );
    return _read(response, 'rename the device');
  }

  static HostnameStatus _read(http.Response response, String context) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return HostnameStatus.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    if (status >= 400 && status < 500) {
      Object? message;
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) message = body['error'];
      } on FormatException {
        message = null;
      }
      throwApiError(status, message, context);
    }
    throw ApiException(status, context);
  }
}
