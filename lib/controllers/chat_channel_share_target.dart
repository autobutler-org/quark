import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/share_target.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/models/path_grant.dart';
import 'package:quark/services/chat_channels_service.dart';

/// Signs the event a member change returned, once it is checked to describe
/// that change.
typedef SignMemberChangeFn =
    Future<void> Function(
      ChatChannelEvent? event, {
      int? userId,
      int? groupId,
      String? level,
    });

/// Gives an account or group a level on a channel.
typedef SetChatMemberFn =
    Future<ChatMembersChange> Function(
      int channelId, {
      int? userId,
      int? groupId,
      required String level,
    });

/// Removes an account's or group's row from a channel.
typedef RemoveChatMemberFn =
    Future<ChatMembersChange> Function(
      int channelId, {
      int? userId,
      int? groupId,
    });

/// A chat channel's members through the share sheet (#2422): users or groups
/// at read (view), write (post) or owner (manage), under
/// `/api/v0/chat/channels/:id/members`.
///
/// Owners and admins manage. A change the Quark answers carries an event,
/// which is signed when it says what was asked, and a removal makes the
/// Quark ask the members who stay to rotate the key. `general`'s `everyone`
/// row is locked. The calls default to [ChatChannelsService] and
/// [ChatChannelKeysController.instance]; tests pass fakes.
class ChatChannelShareTarget extends ShareTarget {
  /// Shares [channel]; [isAdmin] lets an admin manage one they don't own.
  ChatChannelShareTarget({
    required this.channel,
    this.isAdmin = false,
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

  final Future<List<ChatMember>> Function(int channelId) _listMembers;
  final SetChatMemberFn _setMember;
  final RemoveChatMemberFn _removeMember;
  final SignMemberChangeFn _sign;

  @override
  Future<PathAccess> load() async => _access(await _listMembers(channel.id));

  @override
  Future<PathAccess> grant({
    int? userId,
    int? groupId,
    required String level,
  }) async {
    final change = await _setMember(
      channel.id,
      userId: userId,
      groupId: groupId,
      level: level,
    );
    await _sign(change.event, userId: userId, groupId: groupId, level: level);
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

  /// `everyone` can't leave `general`.
  @override
  bool isLocked(PathGrant grant) => channel.isDefault && grant.builtin;

  PathAccess _access(List<ChatMember> members) {
    final canManage = isAdmin || channel.isOwner;
    return PathAccess(
      deviceSerial: '',
      relPath: '',
      canManage: canManage,
      canGrantOwner: canManage,
      grants: [
        for (final m in members)
          PathGrant(
            userId: m.userId,
            groupId: m.groupId,
            name: m.name,
            builtin: m.builtin,
            level: m.level,
            from: '',
          ),
      ],
    );
  }
}
