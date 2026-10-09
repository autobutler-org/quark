import 'dart:convert';

import 'package:quark/models/account_request_decision.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The account request history an admin reads, under
/// `/api/v0/admin/account-requests/history` (#2730). The Quark answers anyone
/// else with 403, which reads as a permission failure through [Errors].
class AccountRequestHistoryService with AuthenticatedService {
  AccountRequestHistoryService._();
  static final AccountRequestHistoryService instance =
      AccountRequestHistoryService._();

  /// The approvals and denials the Quark still keeps, newest first.
  static Future<List<AccountRequestDecision>> list() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/admin/account-requests/history'),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'list account request history');
    }
    return (jsonDecode(response.body) as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AccountRequestDecision.fromJson)
        .toList(growable: false);
  }
}
