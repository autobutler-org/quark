import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/controllers/chat_unread_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_message.dart';
import 'package:quark/services/app_settings.dart';
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
    String? Function(ChatMessage message)? openMessage,
    bool Function()? isUnlocked,
    Listenable? keyChanges,
    int? Function()? currentUserId,
  }) : _unread = unread,
       _ensureKeys =
           ensureKeys ?? ChatChannelKeysController.instance.ensureKeys,
       _listMembers = listMembers,
       _fetchMessages = fetchMessages,
       _openMessage = openMessage ?? _open,
       _isUnlocked =
           isUnlocked ?? (() => ChatKeysController.instance.isUnlocked),
       _keyChanges =
           keyChanges ??
           Listenable.merge([
             ChatKeysController.instance,
             ChatChannelKeysController.instance,
           ]),
       _currentUserId =
           currentUserId ?? (() => AppSettings.instance.userId.value) {
    _unread.addListener(_sync);
    _keyChanges.addListener(_sync);
    _sync();
  }

  final ChatUnreadController _unread;
  final Future<bool> Function(int channelId) _ensureKeys;
  final Future<List<ChatMember>> Function(int channelId) _listMembers;
  final Future<List<ChatMessage>> Function(int channelId, {int? limit})
  _fetchMessages;
  final String? Function(ChatMessage message) _openMessage;
  final bool Function() _isUnlocked;
  final Listenable _keyChanges;
  final int? Function() _currentUserId;

  Map<int, int> _mentions = const {};

  /// The unread count each channel was last read at.
  final Map<int, int> _readAt = {};

  /// The unread messages of each channel that would not open.
  final Map<int, List<ChatMessage>> _unopened = {};

  /// How many unread messages in channel [channelId] mention the signed-in
  /// account; zero for one not read yet.
  int countOf(int channelId) => _mentions[channelId] ?? 0;

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
    final counts = _isUnlocked() ? _unread.counts : const <int, int>{};
    bool isRead(int channelId, _) => (counts[channelId] ?? 0) == 0;
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
      notifyListeners();
    }
    for (final MapEntry(key: channelId, value: count) in counts.entries) {
      if (count == 0 || _readAt[channelId] == count) continue;
      _readAt[channelId] = count;
      unawaited(_read(channelId, count));
    }
  }

  // ponytail: every change of a channel's unread count reads its keys,
  // members and newest page again, and only the newest page is looked at, so
  // a mention more than a page back is missed. Count the mention in the
  // `chat_message_created` event, and page back, if either matters.
  Future<void> _read(int channelId, int count) async {
    try {
      await _ensureKeys(channelId);
      final (members, page) = await (
        _listMembers(channelId),
        _fetchMessages(channelId, limit: ChatMessagesService.maxPage),
      ).wait;
      if (isDisposed || _readAt[channelId] != count) return;
      final me = _currentUserId();
      final name = members.nameOfUser(me);
      final names = members.mentionNames;
      final unopened = <ChatMessage>[];
      var mentions = 0;
      for (final message
          in page.reversed
              .where((m) => !m.isDeleted && m.authorId != me)
              .take(count)) {
        final text = _openMessage(message);
        if (text == null) {
          unopened.add(message);
        } else if (name != null && ChatMentions.mentions(text, names, name)) {
          mentions++;
        }
      }
      if (unopened.isEmpty) {
        _unopened.remove(channelId);
      } else {
        _unopened[channelId] = unopened;
      }
      if (countOf(channelId) == mentions) return;
      _mentions = {..._mentions, channelId: mentions};
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
          ),
        ),
      );
    } on Object {
      return null;
    }
  }
}
