import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/share_target.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/models/path_grant.dart';
import 'package:quark/services/chat_channels_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Signs the event a member change returned, once it is checked to describe
/// that change.
typedef SignMemberChangeFn =
    Future<void> Function(
      ChatChannelEvent? event, {
      int? userId,
      int? groupId,
      Set<ChatPermission>? permissions,
    });

/// Gives an account or group a set of permissions on a channel.
typedef SetChatMemberFn =
    Future<ChatMembersChange> Function(
      int channelId, {
      int? userId,
      int? groupId,
      required Set<ChatPermission> permissions,
    });

/// Removes an account's or group's row from a channel.
typedef RemoveChatMemberFn =
    Future<ChatMembersChange> Function(
      int channelId, {
      int? userId,
      int? groupId,
    });

/// A chat channel's members through the share sheet (#2422): users or groups,
/// each with a set of permissions (#2415), under
/// `/api/v0/chat/channels/:id/members`.
///
/// A holder of `manage_members`, or an admin, manages; they may grant only
/// what they hold ([heldPermissions]), and a row they may not change under
/// the Quark's escalation bound is locked, so the sheet never offers a change
/// the Quark would refuse: a row that isn't a strict subset of theirs unless
/// they hold `manage_channel`, the creator's row unless they are the creator
/// or an admin, and `general`'s `everyone` row for everyone. A change the
/// Quark answers carries an event, which is signed when it says what was
/// asked, and taking `read_messages` away makes the Quark ask the members who
/// keep it to rotate the key. The calls default to [ChatChannelsService] and
/// [ChatChannelKeysController.instance]; tests pass fakes.
class ChatChannelShareTarget extends ShareTarget {
  /// Shares [channel]; [isAdmin] lets an admin manage one they aren't in, and
  /// [selfUserId] is the signed-in account.
  ChatChannelShareTarget({
    required this.channel,
    this.isAdmin = false,
    this.selfUserId,
    Future<List<ChatMember>> Function(int channelId) listMembers =
        ChatChannelsService.listMembers,
    SetChatMemberFn setMember = ChatChannelsService.setMember,
    RemoveChatMemberFn removeMember = ChatChannelsService.removeMember,
    SignMemberChangeFn? signMemberChange,
  }) : _listMembers = listMembers,
       _setMember = setMember,
       _removeMember = removeMember,
       _sign =
           signMemberChange ??
           ChatChannelKeysController.instance.signMemberChange;

  /// The channel whose members are shown.
  final ChatChannel channel;

  /// Whether the signed-in account is an admin.
  final bool isAdmin;

  /// The signed-in account, which may change its own row as the creator.
  final int? selfUserId;

  final Future<List<ChatMember>> Function(int channelId) _listMembers;
  final SetChatMemberFn _setMember;
  final RemoveChatMemberFn _removeMember;
  final SignMemberChangeFn _sign;

  @override
  Set<ChatPermission> get heldPermissions =>
      isAdmin ? ChatPermission.values.toSet() : channel.permissions;

  @override
  Future<PathAccess> load() async => _access(await _listMembers(channel.id));

  /// Channels share sets; [grantPermissions] is the call.
  @override
  Future<PathAccess> grant({
    int? userId,
    int? groupId,
    required String level,
  }) => throw UnsupportedError('a channel shares permission sets');

  @override
  Future<PathAccess> grantPermissions({
    int? userId,
    int? groupId,
    required Set<ChatPermission> permissions,
  }) async {
    final change = await _setMember(
      channel.id,
      userId: userId,
      groupId: groupId,
      permissions: permissions,
    );
    await _sign(
      change.event,
      userId: userId,
      groupId: groupId,
      permissions: permissions,
    );
    return _access(change.members);
  }

  @override
  Future<PathAccess> revoke({int? userId, int? groupId}) async {
    final change = await _removeMember(
      channel.id,
      userId: userId,
      groupId: groupId,
    );
    await _sign(change.event, userId: userId, groupId: groupId);
    return _access(change.members);
  }

  /// `everyone` can't leave `general`, and a row the signed-in account may
  /// not demote or remove under the Quark's bound (#2415) is left alone. An
  /// account's own row is judged by its row, the Quark by its whole set; the
  /// Quark decides.
  @override
  bool isLocked(PathGrant grant) {
    if (channel.isDefault && grant.builtin) return true;
    if (isAdmin) return false;
    final userId = grant.userId;
    if (userId != null && userId == channel.createdBy && userId != selfUserId) {
      return true;
    }
    final held = heldPermissions;
    if (held.contains(ChatPermission.manageChannel)) return false;
    final row = grant.permissions ?? const <ChatPermission>{};
    return !(held.containsAll(row) && row.length < held.length);
  }

  PathAccess _access(List<ChatMember> members) {
    final canManage =
        isAdmin || channel.permissions.contains(ChatPermission.manageMembers);
    return PathAccess(
      deviceSerial: '',
      relPath: '',
      canManage: canManage,
      grants: [
        for (final m in members)
          PathGrant(
            userId: m.userId,
            groupId: m.groupId,
            name: m.name,
            builtin: m.builtin,
            level: 'read',
            permissions: m.permissions,
            from: '',
          ),
      ],
    );
  }
}
