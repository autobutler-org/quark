import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/controllers/chat_unread_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_message.dart';
import 'package:quark/services/chat_channels_service.dart';
import 'package:quark/services/chat_messages_service.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// How many of each channel's unread messages mention the signed-in account
/// (#3157), so a channel that has not been opened can say so.
///
/// A mention is only the text `@name` inside an encrypted message (#2623),
/// so the Quark can't count them. This reads them on the device: for every
/// channel [ChatUnreadController] counts unread messages in, it brings the
/// channel's keys up to date, loads its newest messages and its members,
/// opens the unread ones in memory and counts those that mention the
/// account. Nothing it decrypts is kept.
///
/// - The Quark sends a count, not the read marker, so the unread messages
///   are taken to be the newest that many which someone else wrote and
///   nobody deleted, which is what the Quark counted.
/// - A channel is read again whenever its unread count changes, and dropped
///   when the count reaches zero.
/// - While chat is locked nothing is read and every count is zero; unlocking
///   reads them. A message whose key has not arrived is left out, and the
///   channel is read again once one of them opens.
/// - A channel that fails to load keeps the count it had until its unread
///   count next changes.
/// - In an anonymous channel (#2949) the account is its pseudonym and its
///   alias: what the members and messages there name it by.
/// - Side conversations (#4349): every root in that page whose branch has
///   unread replies has its newest page of replies read the same way. A
///   mention there adds to the channel's count, and to [extraUnreadOf] when
///   the account is not involved in the branch, which is what puts such a
///   branch on the channel's badge. [mentionsInBranch] says which branches
///   hold one, for their chips. The channel on screen is still read, for
///   its chips, but [countOf] and [extraUnreadOf] read zero there, as
///   `ChatUnreadController.countOf` does.
class ChatUnreadMentionsController extends ChangeNotifier with SafeNotifier {
  /// Builds a controller following [unread]. Every other collaborator has a
  /// real default; tests pass fakes. [openMessage] is a message's text, or
  /// null when it won't open.
  ChatUnreadMentionsController({
    required ChatUnreadController unread,
    Future<bool> Function(int channelId)? ensureKeys,
    Future<List<ChatMember>> Function(int channelId) listMembers =
        ChatChannelsService.listMembers,
    Future<List<ChatMessage>> Function(int channelId, {int? limit})
        fetchMessages =
        ChatMessagesService.fetchMessages,
    Future<List<ChatMessage>> Function(int rootId, {int? limit}) fetchReplies =
        ChatMessagesService.fetchReplies,
    String? Function(ChatMessage message)? openMessage,
    bool Function()? isUnlocked,
    Listenable? keyChanges,
    int? Function(int channelId)? selfIdIn,
  }) : _unread = unread,
       _ensureKeys =
           ensureKeys ?? ChatChannelKeysController.instance.ensureKeys,
       _listMembers = listMembers,
       _fetchMessages = fetchMessages,
       _fetchReplies = fetchReplies,
       _openMessage = openMessage ?? _open,
       _isUnlocked =
           isUnlocked ?? (() => ChatKeysController.instance.isUnlocked),
       _keyChanges =
           keyChanges ??
           Listenable.merge([
             ChatKeysController.instance,
             ChatChannelKeysController.instance,
           ]),
       _selfIdIn = selfIdIn ?? ChatChannelKeysController.instance.selfIdIn {
    _unread.addListener(_sync);
    _keyChanges.addListener(_sync);
    _sync();
  }

  final ChatUnreadController _unread;
  final Future<bool> Function(int channelId) _ensureKeys;
  final Future<List<ChatMember>> Function(int channelId) _listMembers;
  final Future<List<ChatMessage>> Function(int channelId, {int? limit})
  _fetchMessages;
  final Future<List<ChatMessage>> Function(int rootId, {int? limit})
  _fetchReplies;
  final String? Function(ChatMessage message) _openMessage;
  final bool Function() _isUnlocked;
  final Listenable _keyChanges;

  /// The id this account goes by in a channel: its pseudonym in an
  /// anonymous one (#2949), where messages and members name it that way.
  final int? Function(int channelId) _selfIdIn;

  Map<int, int> _mentions = const {};

  /// Per channel, the mentions in branches the account is not involved in.
  Map<int, int> _extra = const {};

  /// Per channel, the mentions in each of its branches, by root.
  Map<int, Map<int, int>> _branches = const {};

  /// The unread counts each channel was last read at.
  final Map<int, ChatUnreadSplit> _readAt = {};

  /// The unread messages of each channel that would not open.
  final Map<int, List<ChatMessage>> _unopened = {};

  /// How many unread messages in channel [channelId], its side
  /// conversations' included, mention the signed-in account; zero for one
  /// not read yet and for the channel on screen.
  int countOf(int channelId) =>
      _unread.isViewing(channelId) ? 0 : _mentions[channelId] ?? 0;

  /// How many of [countOf] sit in side conversations the account is not
  /// involved in, which the channel's unread count leaves out (#4349).
  int extraUnreadOf(int channelId) =>
      _unread.isViewing(channelId) ? 0 : _extra[channelId] ?? 0;

  /// How many unread replies in the side conversation of message [rootId]
  /// mention the signed-in account (#4349).
  int mentionsInBranch(int rootId) {
    for (final roots in _branches.values) {
      final found = roots[rootId];
      if (found != null) return found;
    }
    return 0;
  }

  @override
  void dispose() {
    _unread.removeListener(_sync);
    _keyChanges.removeListener(_sync);
    super.dispose();
  }

  /// Reads every channel whose unread count moved since it was last read,
  /// or whose unopened messages now open, and forgets the ones with nothing
  /// unread.
  void _sync() {
    final splits = _isUnlocked()
        ? _unread.splits
        : const <int, ChatUnreadSplit>{};
    bool isRead(int channelId, _) => !splits.containsKey(channelId);
    _readAt.removeWhere(isRead);
    _unopened.removeWhere(isRead);
    _unopened.removeWhere((channelId, messages) {
      final opens = messages.any((m) => _openMessage(m) != null);
      if (opens) _readAt.remove(channelId);
      return opens;
    });
    if (_mentions.keys.any((id) => isRead(id, null))) {
      _mentions = {
        for (final e in _mentions.entries)
          if (!isRead(e.key, null)) e.key: e.value,
      };
      _extra = {
        for (final e in _extra.entries)
          if (!isRead(e.key, null)) e.key: e.value,
      };
      _branches = {
        for (final e in _branches.entries)
          if (!isRead(e.key, null)) e.key: e.value,
      };
      notifyListeners();
    }
    for (final MapEntry(key: channelId, value: split) in splits.entries) {
      if (_readAt[channelId] == split) continue;
      _readAt[channelId] = split;
      unawaited(_read(channelId, split));
    }
  }

  // ponytail: every change of a channel's unread counts reads its keys,
  // members and newest page again, and the newest page of replies of each
  // root in it with unread replies, so a mention more than a page back, or in
  // a branch whose root is, is missed. Count the mention in the
  // `chat_message_created` event, and page back, if either matters.
  Future<void> _read(int channelId, ChatUnreadSplit split) async {
    try {
      await _ensureKeys(channelId);
      final (members, page) = await (
        _listMembers(channelId),
        _fetchMessages(channelId, limit: ChatMessagesService.maxPage),
      ).wait;
      final roots = [
        for (final m in page)
          if ((m.branch?.unreadCount ?? 0) > 0) m,
      ];
      final replies = await Future.wait([
        for (final root in roots)
          _fetchReplies(root.id, limit: ChatMessagesService.maxPage),
      ]);
      if (isDisposed || _readAt[channelId] != split) return;
      final me = _selfIdIn(channelId);
      final name = members.nameOfUser(me);
      final names = members.mentionNames;
      final everyone = members.userIdsHolding(ChatPermission.mentionEveryone);
      final unopened = <ChatMessage>[];
      // The unread [count] newest of [messages] that mention the account.
      int mentionsIn(List<ChatMessage> messages, int count) {
        var mentions = 0;
        for (final message
            in messages.reversed
                .where((m) => !m.isDeleted && m.authorId != me)
                .take(count)) {
          final text = _openMessage(message);
          if (text == null) {
            unopened.add(message);
          } else if (name != null &&
              ChatMentions.mentions(
                text,
                ChatMentions.withEveryone(
                  names,
                  allowed: everyone.contains(message.authorId),
                ),
                name,
              )) {
            mentions++;
          }
        }
        return mentions;
      }

      var mentions = mentionsIn(page, split.channel);
      var extra = 0;
      final branches = <int, int>{};
      for (final (i, root) in roots.indexed) {
        final branch = root.branch!;
        final found = mentionsIn(replies[i], branch.unreadCount);
        if (found == 0) continue;
        branches[root.id] = found;
        mentions += found;
        if (!branch.involved) extra += found;
      }
      if (unopened.isEmpty) {
        _unopened.remove(channelId);
      } else {
        _unopened[channelId] = unopened;
      }
      if ((_mentions[channelId] ?? 0) == mentions &&
          (_extra[channelId] ?? 0) == extra &&
          mapEquals(_branches[channelId] ?? const {}, branches)) {
        return;
      }
      _mentions = {..._mentions, channelId: mentions};
      _extra = {..._extra, channelId: extra};
      _branches = {..._branches, channelId: branches};
      notifyListeners();
    } catch (e) {
      debugPrint(
        '[chat_unread_mentions_controller.dart] channel $channelId: $e',
      );
    }
  }

  /// [message]'s text under the key this account holds for it, or null when
  /// chat is locked, the key has not arrived, or it won't open.
  static String? _open(ChatMessage message) {
    final ciphertext = message.ciphertext;
    final crypto = ChatKeysController.instance.crypto;
    final key = ChatChannelKeysController.instance.keyFor(
      message.channelId,
      message.keyVersion,
    );
    if (ciphertext == null || crypto == null || key == null) return null;
    try {
      return utf8.decode(
        crypto.decrypt(
          ciphertext,
          key,
          additionalData: crypto.messageAad(
            channelId: message.channelId,
            keyVersion: message.keyVersion,
            rootId: message.rootId,
          ),
        ),
      );
    } on Object {
      return null;
    }
  }
}
