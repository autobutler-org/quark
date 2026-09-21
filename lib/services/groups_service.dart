import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/group.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The group routes an admin uses, under `/api/v0/admin/groups` (#1910). The
/// Quark answers anyone else with 403.
///
/// A refusal the Quark explains in its own words, such as "a group with that
/// name already exists", goes through [throwApiError], which passes that text
/// on. Two answers get the app's copy instead: 403 reads as a permission
/// failure through [Errors], and adding an account the Quark won't take
/// becomes [Errors.cannotJoinGroup].
class GroupsService with AuthenticatedService {
  GroupsService._();
  static final GroupsService instance = GroupsService._();

  /// What the Quark says when the account being added is missing, waiting for
  /// approval, or turned off. It names a username, but the route takes an id,
  /// so the app words it itself.
  static const _accountCannotJoin = 'no account has that username';

  /// Every group, `everyone` first, each with its members.
  static Future<List<Group>> list() async {
    final response = await instance.authenticatedGet(_groupsUri());
    _check(response, 'list groups');
    return (jsonDecode(response.body) as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Group.fromJson)
        .toList(growable: false);
  }

  /// Creates a group named [name], with no members.
  static Future<void> create(String name) async {
    final response = await instance.authenticatedPost(
      _groupsUri(),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );
    _check(response, 'create group');
  }

  /// Renames the group [id] to [name]. The Quark's answer leaves the members
  /// out, so a caller lists the groups again rather than reading it.
  static Future<void> rename(int id, String name) async {
    final response = await instance.authenticatedPut(
      _groupsUri('/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );
    _check(response, 'rename group $id');
  }

  /// Deletes the group [id]. Whatever was shared with it stops being shared
  /// with its members.
  static Future<void> delete(int id) async {
    final response = await instance.authenticatedDelete(_groupsUri('/$id'));
    _check(response, 'delete group $id');
  }

  /// Adds the account [userId] to the group [groupId]. Adding a member twice
  /// changes nothing. Only an account that can sign in can be added.
  static Future<void> addMember(int groupId, int userId) async {
    final response = await instance.authenticatedPut(
      _groupsUri('/$groupId/members/$userId'),
    );
    if (response.statusCode == 404 &&
        _errorText(response.body) == _accountCannotJoin) {
      throw const MessageException(Errors.cannotJoinGroup);
    }
    _check(response, 'add member $userId to group $groupId');
  }

  /// Takes the account [userId] out of the group [groupId].
  static Future<void> removeMember(int groupId, int userId) async {
    final response = await instance.authenticatedDelete(
      _groupsUri('/$groupId/members/$userId'),
    );
    _check(response, 'remove member $userId from group $groupId');
  }

  static Uri _groupsUri([String suffix = '']) =>
      apiBaseUri.resolve('/api/v0/admin/groups$suffix');

  /// Throws for a refused [response].
  static void _check(http.Response response, String context) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    if (status == 403) throw ApiException(status, context);
    throwApiError(status, _errorText(response.body), context);
  }

  static Object? _errorText(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? decoded['error'] : null;
    } on FormatException {
      return null;
    }
  }
}
