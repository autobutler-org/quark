import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/models/chat_message.dart';
import 'package:quark/models/chat_poll.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/chat_attachment_message.dart';
import 'package:quark/services/chat_attachment_save.dart';
import 'package:quark/services/chat_channel_keys_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/chat_messages_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:sodium/sodium_sumo.dart';

/// Writes a decrypted attachment through the platform save.
typedef SaveChatAttachmentFn =
    Future<String?> Function({
      required Stream<List<int>> plaintext,
      required String fileName,
    });

/// Uploads a decrypted attachment into a Quark folder under its file name.
typedef UploadChatAttachmentFn =
    Future<void> Function({
      required Stream<List<int>> plaintext,
      required String folder,
      required String fileName,
    });

/// One open channel's timeline (#2418): its messages, decrypted in memory,
/// merged with its membership and key events.
///
/// - [open] loads the newest page and the channel's events, and follows the
///   events socket: `chat_message_created` and `chat_message_deleted` for
///   messages, `chat_channel_changed` for events (a new one, or one its actor
///   just signed).
/// - The socket drops events when a client falls behind and has no replay.
///   [open] fetches `?after=` the newest id held, and [catchUp], on every
///   reconnect and refresh, reads the whole loaded window again from the
///   oldest id held, so reactions and deletions it missed land too.
/// - [send] encrypts under the channel's current key version, binding the
///   channel id and version as additional data, and posts. [delete]
///   tombstones.
/// - [toggleReaction] adds or takes back this account's reaction (#2426),
///   encrypted like a message and bound to the message and account too, and
///   `chat_reaction_changed` keeps everyone's reactions current. A
///   tombstone has none.
/// - [sendPoll] posts a poll (#3894): its question in the encrypted text,
///   its settings beside it for the Quark to enforce. [answerPoll] encrypts
///   this account's answer, padded so every answer is one size, and
///   [closePoll] closes one of this account's own. `chat_poll_answer_changed`
///   keeps a poll that names respondents current. An anonymous poll sends
///   `chat_poll_answers_changed` with no answer, and the answers are read
///   again. `chat_poll_closed` closes it here, and [pollItemFor] tallies one
///   on this device.
/// - A message under a key version this account has no grant of yet is
///   [ChatMessageState.waiting], and opens by itself once the grant lands
///   (the keys controller notifies).
/// - [entries] is the merged timeline, oldest first.
///
/// Plaintext stays in memory, and [dispose] drops it, except when an
/// attachment is saved. That writes the file to a temporary file and deletes
/// it afterward. Saving into Quark files uploads that plaintext through the
/// files upload; the Quark does not decrypt it. The chat page makes one per
/// open channel and disposes it on leaving.
class ChatMessagesController extends ChangeNotifier with SafeNotifier {
  /// Builds a controller for [channelId]. Every collaborator has a real
  /// default; tests pass fakes.
  ChatMessagesController({
    required this.channelId,
    ChatChannelKeysController? keys,
    ChatCrypto? Function()? crypto,
    Future<List<ChatMessage>> Function(
      int channelId, {
      int? before,
      int? after,
      int? limit,
    })?
    fetchMessages,
    Future<ChatMessage> Function(
      int channelId,
      int keyVersion,
      Uint8List ciphertext, {
      String? clientMessageId,
      List<String>? attachmentIds,
      ChatPoll? poll,
    })?
    postMessage,
    Future<ChatMessage> Function(int messageId)? deleteMessage,
    Future<ChatReaction> Function(
      int messageId,
      int keyVersion,
      Uint8List ciphertext,
    )?
    addReaction,
    Future<void> Function(int reactionId)? deleteReaction,
    Future<ChatPollResponse> Function(
      int messageId,
      int keyVersion,
      Uint8List ciphertext,
    )?
    answerPoll,
    Future<List<ChatPollResponse>> Function(int messageId)? fetchPollAnswers,
    Future<ChatPoll> Function(int messageId)? closePoll,
    Future<int> Function(int channelId, String id, Object body)? putAttachment,
    Future<Stream<List<int>>> Function(
      int channelId,
      String id, {
      StreamSink<List<int>>? sink,
    })?
    getAttachment,
    int? Function()? currentUserId,
    Future<List<ChatChannelEvent>> Function(int channelId, {int after})?
    fetchEvents,
    Stream<FileEvent>? events,
    Stream<void>? reconnects,
    SaveChatAttachmentFn? saveAttachmentFile,
    UploadChatAttachmentFn? uploadAttachmentFile,
  }) : _keys = keys ?? ChatChannelKeysController.instance,
       _crypto = crypto ?? (() => ChatKeysController.instance.crypto),
       _fetchMessages = fetchMessages ?? ChatMessagesService.fetchMessages,
       _postMessage = postMessage ?? ChatMessagesService.postMessage,
       _deleteMessage = deleteMessage ?? ChatMessagesService.deleteMessage,
       _addReaction = addReaction ?? ChatMessagesService.addReaction,
       _deleteReaction = deleteReaction ?? ChatMessagesService.deleteReaction,
       _answerPoll = answerPoll ?? ChatMessagesService.answerPoll,
       _fetchPollAnswers =
           fetchPollAnswers ?? ChatMessagesService.fetchPollAnswers,
       _closePoll = closePoll ?? ChatMessagesService.closePoll,
       _putAttachment = putAttachment ?? ChatMessagesService.putAttachment,
       _getAttachment = getAttachment ?? ChatMessagesService.getAttachment,
       _currentUserId =
           currentUserId ?? (() => AppSettings.instance.userId.value),
       _fetchEvents = fetchEvents ?? ChatChannelKeysService.fetchEvents,
       _eventStream = events ?? EventsService.instance.events,
       _reconnectStream = reconnects ?? EventsService.instance.reconnects,
       _saveAttachmentFile = saveAttachmentFile ?? saveChatAttachmentToDevice,
       _uploadAttachmentFile =
           uploadAttachmentFile ?? uploadChatAttachmentToFolder;

  /// The channel this timeline is for.
  final int channelId;

  /// Messages per page of history.
  static const pageSize = 50;

  /// Events per page, the Quark's cap.
  static const _eventsPage = 200;

  final ChatChannelKeysController _keys;
  final ChatCrypto? Function() _crypto;
  final Future<List<ChatMessage>> Function(
    int channelId, {
    int? before,
    int? after,
    int? limit,
  })
  _fetchMessages;
  final Future<ChatMessage> Function(
    int channelId,
    int keyVersion,
    Uint8List ciphertext, {
    String? clientMessageId,
    List<String>? attachmentIds,
    ChatPoll? poll,
  })
  _postMessage;
  final Future<ChatMessage> Function(int messageId) _deleteMessage;
  final Future<ChatReaction> Function(
    int messageId,
    int keyVersion,
    Uint8List ciphertext,
  )
  _addReaction;
  final Future<void> Function(int reactionId) _deleteReaction;
  final Future<ChatPollResponse> Function(
    int messageId,
    int keyVersion,
    Uint8List ciphertext,
  )
  _answerPoll;
  final Future<List<ChatPollResponse>> Function(int messageId)
  _fetchPollAnswers;
  final Future<ChatPoll> Function(int messageId) _closePoll;
  final Future<int> Function(int channelId, String id, Object body)
  _putAttachment;
  final Future<Stream<List<int>>> Function(
    int channelId,
    String id, {
    StreamSink<List<int>>? sink,
  })
  _getAttachment;

  /// The most bytes of an image this client decodes into memory. A larger
  /// image is refused before the download starts.
  static const maxInlineImageBytes = 20 << 20;
  final int? Function() _currentUserId;
  final Future<List<ChatChannelEvent>> Function(int channelId, {int after})
  _fetchEvents;
  final Stream<FileEvent> _eventStream;
  final Stream<void> _reconnectStream;
  final SaveChatAttachmentFn _saveAttachmentFile;
  final UploadChatAttachmentFn _uploadAttachmentFile;

  final SplayTreeMap<int, ChatTimelineMessage> _messages = SplayTreeMap();
  List<ChatTimelineSystem> _system = const [];
  final List<StreamSubscription<Object?>> _subs = [];
  Future<void>? _catchingUp;

  /// Whether older messages may exist before the oldest one loaded.
  bool hasOlder = true;

  /// True while [open] runs, before anything is shown.
  bool isLoading = false;

  /// What went wrong in the last [open], [catchUp] or [loadOlder], for
  /// `Errors.message`; null when it worked.
  Object? error;

  /// The id of the newest message loaded, deleted ones included; null with
  /// none. What a read marker moves to (#2424).
  int? get newestMessageId => _messages.lastKey();

  /// The timeline, oldest first: messages and system events merged by time,
  /// a system event first when both share a second. Events older than the
  /// loaded history are left out until [loadOlder] reaches them.
  List<ChatTimelineEntry> get entries {
    final oldest = hasOlder && _messages.isNotEmpty
        ? _messages[_messages.firstKey()]!.createdAt
        : null;
    final merged = <ChatTimelineEntry>[
      for (final s in _system)
        if (oldest == null || !s.createdAt.isBefore(oldest)) s,
      ..._messages.values,
    ];
    // ponytail: re-sorted per read; cache it if a long channel stutters.
    merged.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      if (byTime != 0) return byTime;
      if (a is ChatTimelineSystem && b is ChatTimelineMessage) return -1;
      if (a is ChatTimelineMessage && b is ChatTimelineSystem) return 1;
      return _idOf(a).compareTo(_idOf(b));
    });
    return merged;
  }

  /// Loads the newest page and the channel's events, and starts following the
  /// socket. Failures land in [error].
  Future<void> open() async {
    if (_subs.isEmpty) {
      _subs
        ..add(_eventStream.listen(_onEvent))
        ..add(_reconnectStream.listen((_) => catchUp()));
      _keys.addListener(_onKeysChanged);
    }
    isLoading = true;
    notifyListeners();
    try {
      await _keys.ensureKeys(channelId);
      final page = await _fetchMessages(channelId, limit: pageSize);
      hasOlder = page.length == pageSize;
      page.forEach(_put);
      await _sync(() => _messages.isEmpty ? 0 : _messages.lastKey()!);
      error = null;
    } catch (e) {
      error = e;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Fetches every message from the oldest one held on, again, so newer
  /// messages and any deletions and reactions the socket dropped land, and
  /// the channel's events. Concurrent calls share one run.
  // ponytail: rereads the whole loaded window; page reactions separately if
  // long sessions make reconnects heavy.
  Future<void> catchUp() =>
      _sync(() => _messages.isEmpty ? 0 : _messages.firstKey()! - 1);

  /// Loads the page before the oldest message held.
  Future<void> loadOlder() async {
    if (!hasOlder || _messages.isEmpty) return;
    try {
      final page = await _fetchMessages(
        channelId,
        before: _messages.firstKey(),
        limit: pageSize,
      );
      hasOlder = page.length == pageSize;
      page.forEach(_put);
      error = null;
    } catch (e) {
      error = e;
    }
    notifyListeners();
  }

  /// Encrypts [text] under the channel's current key and posts it. Throws a
  /// [MessageException] while waiting for the key or when the message is over
  /// the Quark's cap; network failures propagate as the service throws them.
  ///
  /// A retry encrypts again under a fresh nonce, so it passes the
  /// [clientMessageId] its first attempt did: that is how the Quark knows a
  /// send whose response was lost and answers with the stored message.
  Future<void> send(String text, {String? clientMessageId}) => _post(
    text,
    clientMessageId: clientMessageId,
    tooLong: Errors.chatMessageTooLong,
  );

  /// Posts [draft] as a poll: its question encrypted like a message, its
  /// settings in the clear for the Quark to enforce. Throws like [send].
  Future<void> sendPoll(ChatPollDraft draft) => _post(
    ChatPollQuestion.fromDraft(draft).toPayload(),
    poll: ChatPoll(
      closesAt: draft.closesAt,
      allowChange: draft.allowChange,
      anonymous: draft.anonymous,
      resultsAfterClose: draft.resultsAfterClose,
    ),
    tooLong: Errors.chatPollTooLong,
  );

  Future<void> _post(
    String text, {
    required String tooLong,
    String? clientMessageId,
    ChatPoll? poll,
  }) async {
    final (crypto, version, key) = await _currentKey();
    final ciphertext = crypto.encrypt(
      Uint8List.fromList(utf8.encode(text)),
      key,
      additionalData: crypto.messageAad(
        channelId: channelId,
        keyVersion: version,
      ),
    );
    if (ciphertext.length > ChatMessagesService.maxCiphertextBytes) {
      throw MessageException(tooLong);
    }
    final stored = await _postMessage(
      channelId,
      version,
      ciphertext,
      clientMessageId: clientMessageId,
      poll: poll,
    );
    _put(stored, text: text);
    notifyListeners();
  }

  /// Seals [bytes] as one attachment, uploads it, and posts the message.
  ///
  /// [caption] may be empty: a file with no caption is still a message. The
  /// stored row is opened again so the timeline carries the file's name and
  /// key, the same way a message loaded later does. Throws like [send] when
  /// the channel key is missing, and whatever the upload or the post throws.
  Future<void> sendAttachment({
    required String name,
    required String mime,
    required Uint8List bytes,
    String caption = '',
    String? clientMessageId,
  }) async {
    final (crypto, version, key) = await _currentKey();
    final prepared = await prepareAttachmentMessage(
      crypto: crypto,
      channelId: channelId,
      keyVersion: version,
      channelKey: key,
      text: caption,
      files: [AttachmentPlaintext(name: name, mime: mime, bytes: bytes)],
    );
    for (var i = 0; i < prepared.attachmentIds.length; i++) {
      await _putAttachment(
        channelId,
        prepared.attachmentIds[i],
        prepared.sealedBytes[i],
      );
    }
    final stored = await _postMessage(
      channelId,
      version,
      prepared.ciphertext,
      clientMessageId: clientMessageId,
      attachmentIds: prepared.attachmentIds,
    );
    // Decrypt the post we just made so the row has the caption and the
    // file key. Passing the caption alone would drop the attachment.
    _put(stored);
    notifyListeners();
  }

  /// The thumbnail bytes for [attachmentId], or null when that file has none.
  Uint8List? thumbnailFor(String attachmentId) {
    final thumb = _described(attachmentId)?.thumbnail;
    if (thumb == null || thumb.isEmpty) return null;
    return thumb;
  }

  /// Decrypts image [attachmentId] into memory.
  ///
  /// Refuses a file larger than [maxInlineImageBytes] before downloading it.
  /// Throws [StateError] when the file is missing, too large, or chat is
  /// locked, and whatever the download or the decrypt throws.
  Future<Uint8List> readImageAttachment(String attachmentId) async {
    final described = _described(attachmentId);
    if (described == null) {
      throw StateError('no attachment $attachmentId');
    }
    if (described.size > maxInlineImageBytes) {
      throw StateError('attachment $attachmentId is ${described.size} bytes');
    }
    final crypto = _crypto();
    if (crypto == null) throw StateError('chat is locked');
    final sealed = await _getAttachment(channelId, described.id);
    final key = crypto.sodium.secureCopy(described.key);
    final builder = BytesBuilder(copy: false);
    try {
      await for (final part in crypto.openAttachment(
        key: key,
        noncePrefix: described.nonce,
        input: sealed,
        totalBytes: described.size,
      )) {
        if (builder.length + part.length > maxInlineImageBytes) {
          throw StateError(
            'attachment $attachmentId is larger than $maxInlineImageBytes bytes',
          );
        }
        builder.add(part);
      }
    } finally {
      key.dispose();
    }
    return builder.takeBytes();
  }

  /// Saves [attachmentId] through the platform save, under the file's own name.
  ///
  /// Returns where it landed, or null when the person canceled. A picture or
  /// video on a phone goes to the photo library. This does not apply
  /// [maxInlineImageBytes]: that cap is only for opening an image in memory.
  Future<String?> saveAttachmentToDevice(String attachmentId) {
    final name = _attachmentSaveName(attachmentId);
    return _saveAttachmentFile(
      plaintext: openAttachmentPlaintext(attachmentId),
      fileName: name,
    );
  }

  /// Uploads [attachmentId] into [folder] under the file's own name.
  ///
  /// [folder] is the folder the person picked, `/` for the top of their
  /// files. A name already there is kept beside the new file. The plaintext
  /// is streamed; it is not collected here.
  Future<void> saveAttachmentToFolder(
    String attachmentId, {
    required String folder,
  }) {
    final name = _attachmentSaveName(attachmentId);
    return _uploadAttachmentFile(
      plaintext: openAttachmentPlaintext(attachmentId),
      folder: folder,
      fileName: name,
    );
  }

  String _attachmentSaveName(String attachmentId) {
    final described = _described(attachmentId);
    if (described == null) {
      throw StateError('no attachment $attachmentId');
    }
    final base = described.name.trim().split(RegExp(r'[/\\]')).last.trim();
    if (base.isEmpty || base == '.' || base == '..') return 'file';
    return base;
  }

  /// Decrypts [attachmentId] one chunk at a time.
  ///
  /// Nothing is buffered into one list. The caller writes the chunks out.
  /// The file key stays alive until the stream finishes or is canceled.
  Stream<List<int>> openAttachmentPlaintext(String attachmentId) async* {
    final described = _described(attachmentId);
    if (described == null) {
      throw StateError('no attachment $attachmentId');
    }
    final crypto = _crypto();
    if (crypto == null) throw StateError('chat is locked');
    final sealed = await _getAttachment(channelId, described.id);
    final key = crypto.sodium.secureCopy(described.key);
    try {
      yield* crypto.openAttachment(
        key: key,
        noncePrefix: described.nonce,
        input: sealed,
        totalBytes: described.size,
      );
    } finally {
      key.dispose();
    }
  }

  ChatOpenAttachment? _described(String attachmentId) {
    for (final entry in _messages.values) {
      for (final file in entry.attachments) {
        if (file.id == attachmentId) return file;
      }
    }
    return null;
  }

  /// Answers poll [messageId] with [answer], padded to one size and
  /// encrypted under the channel's current key, bound to the poll and,
  /// unless it is anonymous, this account. Throws like [send]; the Quark's
  /// refusals of a closed poll or a second answer come back as it words them.
  Future<void> answerPoll(int messageId, ChatPollAnswer answer) async {
    final held = _messages[messageId];
    final poll = held?.message.poll;
    final question = held?.question;
    final me = _currentUserId();
    if (poll == null || question == null || me == null) return;
    final (crypto, version, key) = await _currentKey();
    final ciphertext = crypto.encrypt(
      ChatCrypto.padPollAnswer(question.encodeAnswer(answer)),
      key,
      additionalData: crypto.pollAnswerAad(
        channelId: channelId,
        keyVersion: version,
        messageId: messageId,
        userId: poll.anonymous ? null : me,
      ),
    );
    _putAnswer(
      messageId,
      (await _answerPoll(messageId, version, ciphertext)).asMine(),
    );
  }

  /// Closes poll [messageId], one this account posted.
  Future<void> closePoll(int messageId) async {
    final closed = await _closePoll(messageId);
    _changePoll(messageId, (poll) => poll.copyWith(closed: closed.closed));
  }

  /// [entry]'s poll as `QuarkPollCard` draws it, tallied here from the
  /// answers that opened: a count per option, the written answers, the
  /// ratings, and account [me]'s own. Its results are visible unless it
  /// shows them after it closes, is still open at [now], and [me] isn't its
  /// author. Call it only for an entry with a [ChatTimelineMessage.question].
  static ChatPollItem pollItemFor(
    ChatTimelineMessage entry, {
    int? me,
    DateTime? now,
  }) {
    final root = entry.question!;
    final poll = entry.message.poll!;
    final isClosed = poll.isClosedAt(now ?? DateTime.now());
    final questions = root.questions;
    final tallies = [
      for (final question in questions) _QuestionTally(question),
    ];
    ChatPollAnswer? mine;
    var responses = 0;
    for (final ChatOpenPollAnswer(:response, :answer) in entry.pollAnswers) {
      if (answer == null) continue;
      responses++;
      final parts = questions.length == 1 ? [answer] : answer.parts;
      for (final (index, tally) in tallies.indexed) {
        if (index >= parts.length) continue;
        tally.add(parts[index]);
        if (response.mine || (me != null && response.userId == me)) {
          tally.mine = parts[index];
        }
      }
      if (response.mine || (me != null && response.userId == me)) {
        mine = answer;
      }
    }
    final items = [for (final tally in tallies) tally.item];
    final first = items.first;
    return ChatPollItem(
      prompt: first.prompt,
      type: first.type,
      options: first.options,
      counts: first.counts,
      textAnswers: first.textAnswers,
      scale: first.scale,
      ratingCounts: first.ratingCounts,
      questions: items,
      responseCount: responses,
      myAnswer: mine,
      isClosed: isClosed,
      closesAt: poll.closesAt?.toLocal(),
      allowChange: poll.allowChange,
      anonymous: poll.anonymous,
      resultsAfterClose: poll.resultsAfterClose,
      resultsVisible:
          !poll.resultsAfterClose ||
          isClosed ||
          (me != null && entry.message.authorId == me),
    );
  }

  /// Deletes message [messageId]: this account's own, or anyone's in a
  /// channel it owns.
  Future<void> delete(int messageId) async {
    _put(await _deleteMessage(messageId));
    notifyListeners();
  }

  /// Adds this account's [emoji] reaction to message [messageId], or takes
  /// it back when this account already reacted with it. Throws like [send].
  Future<void> toggleReaction(int messageId, String emoji) async {
    final held = _messages[messageId];
    final me = _currentUserId();
    if (held == null || held.message.isDeleted || me == null) return;
    final mine = {
      for (final r in held.reactions)
        if (r.reaction.userId == me && r.emoji == emoji) r.reaction.id,
    };
    if (mine.isNotEmpty) {
      for (final id in mine) {
        await _deleteReaction(id);
      }
      _changeReactions(messageId, remove: mine);
      return;
    }
    final (crypto, version, key) = await _currentKey();
    final ciphertext = crypto.encrypt(
      ChatCrypto.padReaction(emoji),
      key,
      additionalData: crypto.reactionAad(
        channelId: channelId,
        keyVersion: version,
        messageId: messageId,
        userId: me,
      ),
    );
    _changeReactions(
      messageId,
      add: await _addReaction(messageId, version, ciphertext),
    );
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _keys.removeListener(_onKeysChanged);
    _messages.clear();
    _system = const [];
    super.dispose();
  }

  /// The channel's current key and its version, fetching the keys once when
  /// this account holds none. Throws a [MessageException] while waiting for
  /// a member to share it, and a [StateError] while chat is locked.
  Future<(ChatCrypto, int, SecureKey)> _currentKey() async {
    final crypto = _crypto();
    if (crypto == null) throw StateError('chat is locked');
    var version = _keys.currentVersion(channelId);
    var key = _keys.keyFor(channelId, version);
    if (key == null) {
      await _keys.ensureKeys(channelId);
      version = _keys.currentVersion(channelId);
      key = _keys.keyFor(channelId, version);
    }
    if (key == null) throw const MessageException(Errors.chatWaitingForKey);
    return (crypto, version, key);
  }

  /// Fetches every message after [from]'s id, and the channel's events.
  /// Concurrent calls share one run.
  Future<void> _sync(int Function() from) =>
      _catchingUp ??= _catchUp(from()).whenComplete(() {
        _catchingUp = null;
      });

  Future<void> _catchUp(int from) async {
    try {
      var after = from;
      while (true) {
        final page = await _fetchMessages(
          channelId,
          after: after,
          limit: ChatMessagesService.maxPage,
        );
        if (isDisposed) return;
        page.forEach(_put);
        if (page.length < ChatMessagesService.maxPage) break;
        after = page.last.id;
      }
      await _reloadEvents();
      error = null;
    } catch (e) {
      error = e;
    }
    notifyListeners();
  }

  /// Fetches every event again, since a signature can land on an old one.
  // ponytail: whole list each time; page after the newest verified event if
  // a channel's history of joins and rotations grows long.
  Future<void> _reloadEvents() async {
    final events = <ChatChannelEvent>[];
    while (true) {
      final page = await _fetchEvents(
        channelId,
        after: events.isEmpty ? 0 : events.last.id,
      );
      events.addAll(page);
      if (page.length < _eventsPage) break;
    }
    if (isDisposed) return;
    _system = [
      for (final e in events)
        ChatTimelineSystem(event: e, isVerified: _keys.verifyEvent(e)),
    ];
  }

  /// Stores [message], decrypting it unless [text] is already known.
  void _put(ChatMessage message, {String? text}) {
    if (message.channelId != channelId) return;
    _messages[message.id] = text != null && !message.isDeleted
        ? _entry(message, ChatMessageState.ready, text)
        : _open(message);
  }

  /// [message] in the timeline as [state], with [text] when it opened, and
  /// its reactions and, for a poll whose text carries a question, its
  /// answers opened.
  ChatTimelineMessage _entry(
    ChatMessage message,
    ChatMessageState state, [
    String? text,
    List<ChatOpenAttachment> attachments = const [],
  ]) {
    final poll = message.poll;
    final question = poll == null || text == null
        ? null
        : ChatPollQuestion.parse(text);
    return ChatTimelineMessage(
      message: message,
      state: state,
      text: text,
      reactions: _openReactions(message),
      attachments: attachments,
      question: question,
      pollAnswers: poll == null || question == null
          ? const []
          : _openPollAnswers(message.id, poll, question),
    );
  }

  /// Puts [answer] among poll [messageId]'s answers, over the one with its
  /// id, which an answer keeps when it changes. An event never says the
  /// answer is this account's, so one already marked so stays marked.
  void _putAnswer(int messageId, ChatPollResponse answer) =>
      _changePoll(messageId, (poll) {
        final held = poll.answers.where((a) => a.id == answer.id).firstOrNull;
        final next = held != null && held.mine ? answer.asMine() : answer;
        return poll.copyWith(
          answers: [
            for (final a in poll.answers) a.id == answer.id ? next : a,
            if (held == null) next,
          ],
        );
      });

  /// Replaces poll [messageId]'s state with [change] of it, reusing the
  /// message's decrypted text.
  void _changePoll(int messageId, ChatPoll Function(ChatPoll poll) change) {
    final held = _messages[messageId];
    final poll = held?.message.poll;
    if (held == null || poll == null) return;
    _messages[messageId] = _entry(
      held.message.copyWith(poll: change(poll)),
      held.state,
      held.text,
      held.attachments,
    );
    notifyListeners();
  }

  /// Fetches poll [messageId]'s answers again, as a results-after-close poll
  /// closing makes everyone's visible.
  Future<void> _reloadAnswers(int messageId) async {
    final answers = await _fetchPollAnswers(messageId);
    if (isDisposed) return;
    _changePoll(messageId, (poll) => poll.copyWith(answers: answers));
  }

  /// Decrypts [poll]'s answers to [question]; one without its key, that
  /// won't open, or that doesn't fit the question has no answer.
  List<ChatOpenPollAnswer> _openPollAnswers(
    int messageId,
    ChatPoll poll,
    ChatPollQuestion question,
  ) {
    final crypto = _crypto();
    return List.unmodifiable([
      for (final response in poll.answers)
        ChatOpenPollAnswer(
          response: response,
          answer: crypto == null
              ? null
              : _openPollAnswer(crypto, messageId, poll, question, response),
        ),
    ]);
  }

  ChatPollAnswer? _openPollAnswer(
    ChatCrypto crypto,
    int messageId,
    ChatPoll poll,
    ChatPollQuestion question,
    ChatPollResponse response,
  ) {
    final key = _keys.keyFor(channelId, response.keyVersion);
    final userId = response.userId;
    if (key == null || (!poll.anonymous && userId == null)) return null;
    try {
      return question.decodeAnswer(
        ChatCrypto.stripPadding(
          crypto.decrypt(
            response.ciphertext,
            key,
            additionalData: crypto.pollAnswerAad(
              channelId: channelId,
              keyVersion: response.keyVersion,
              messageId: messageId,
              userId: poll.anonymous ? null : userId,
            ),
          ),
        ),
      );
    } on Object catch (e) {
      debugPrint(
        '[chat_messages_controller.dart] poll answer ${response.id} in '
        'channel $channelId won\'t open: $e',
      );
      return null;
    }
  }

  /// Adds [add] to, or drops the ids in [remove] from, message [messageId]'s
  /// reactions, reusing its decrypted text.
  void _changeReactions(
    int messageId, {
    ChatReaction? add,
    Set<int> remove = const {},
  }) {
    final held = _messages[messageId];
    if (held == null || held.message.isDeleted) return;
    final message = held.message.withReactions([
      for (final r in held.message.reactions)
        if (!remove.contains(r.id) && r.id != add?.id) r,
      ?add,
    ]);
    _messages[messageId] = _entry(
      message,
      held.state,
      held.text,
      held.attachments,
    );
    notifyListeners();
  }

  /// Decrypts [message]'s reactions; one without its key, or that won't
  /// open, has no emoji.
  List<ChatOpenReaction> _openReactions(ChatMessage message) {
    if (message.isDeleted) return const [];
    final crypto = _crypto();
    return List.unmodifiable([
      for (final reaction in message.reactions)
        ChatOpenReaction(
          reaction: reaction,
          emoji: crypto == null ? null : _openReaction(crypto, reaction),
        ),
    ]);
  }

  String? _openReaction(ChatCrypto crypto, ChatReaction reaction) {
    final key = _keys.keyFor(channelId, reaction.keyVersion);
    if (key == null) return null;
    try {
      return ChatCrypto.stripPadding(
        crypto.decrypt(
          reaction.ciphertext,
          key,
          additionalData: crypto.reactionAad(
            channelId: channelId,
            keyVersion: reaction.keyVersion,
            messageId: reaction.messageId,
            userId: reaction.userId,
          ),
        ),
      );
    } on Object catch (e) {
      debugPrint(
        '[chat_messages_controller.dart] reaction ${reaction.id} in channel '
        '$channelId won\'t open: $e',
      );
      return null;
    }
  }

  ChatTimelineMessage _open(ChatMessage message) {
    final ciphertext = message.ciphertext;
    if (message.isDeleted || ciphertext == null) {
      return _entry(message, ChatMessageState.deleted);
    }
    final key = _keys.keyFor(channelId, message.keyVersion);
    final crypto = _crypto();
    if (key == null || crypto == null) {
      return _entry(message, ChatMessageState.waiting);
    }
    try {
      final plain = crypto.decrypt(
        ciphertext,
        key,
        additionalData: crypto.messageAad(
          channelId: channelId,
          keyVersion: message.keyVersion,
        ),
      );
      final decoded = decodeAttachmentMessage(plain);
      if (decoded != null) {
        return _entry(message, ChatMessageState.ready, decoded.text, [
          for (final file in decoded.attachments)
            ChatOpenAttachment(
              id: file.id,
              name: file.name,
              mime: file.mime,
              size: file.size,
              key: file.key,
              nonce: file.nonce,
              thumbnail: file.thumbnail,
            ),
        ]);
      }
      return _entry(message, ChatMessageState.ready, utf8.decode(plain));
    } on Object catch (e) {
      debugPrint(
        '[chat_messages_controller.dart] message ${message.id} in channel '
        '$channelId won\'t open: $e',
      );
      return _entry(message, ChatMessageState.unreadable);
    }
  }

  /// Opens waiting messages and reactions whose key just landed, and drops
  /// the text of any whose key is gone, as when chat locks and the keys are
  /// forgotten.
  void _onKeysChanged() {
    var changed = false;
    bool keyless(int version) =>
        _crypto() == null || _keys.keyFor(channelId, version) == null;
    for (final entry in _messages.values.toList()) {
      final stale =
          switch (entry.state) {
            ChatMessageState.waiting => !keyless(entry.message.keyVersion),
            ChatMessageState.ready => keyless(entry.message.keyVersion),
            _ => false,
          } ||
          entry.reactions.any(
            (r) => (r.emoji == null) != keyless(r.reaction.keyVersion),
          ) ||
          entry.pollAnswers.any(
            (a) => (a.answer == null) != keyless(a.response.keyVersion),
          );
      if (!stale) continue;
      _messages[entry.message.id] = _open(entry.message);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _onEvent(FileEvent event) {
    final data = event.data;
    if (data is! Map || (data['channelId'] as num?)?.toInt() != channelId) {
      return;
    }
    switch (event.kind) {
      case 'chat_message_created':
        final message = data['message'];
        if (message is! Map<String, dynamic>) return;
        _put(ChatMessage.fromJson(message));
        notifyListeners();
      case 'chat_message_deleted':
        final id = (data['messageId'] as num?)?.toInt();
        final held = _messages[id];
        if (held == null) return;
        _put(held.message.tombstone(DateTime.now().toUtc()));
        notifyListeners();
      case 'chat_reaction_changed':
        final messageId = (data['messageId'] as num?)?.toInt();
        final reactionId = (data['reactionId'] as num?)?.toInt();
        final reaction = data['reaction'];
        if (messageId == null || reactionId == null) return;
        _changeReactions(
          messageId,
          add: reaction is Map<String, dynamic>
              ? ChatReaction.fromJson(reaction)
              : null,
          remove: {reactionId},
        );
      case 'chat_poll_answer_changed':
        final messageId = (data['messageId'] as num?)?.toInt();
        final answer = data['answer'];
        if (messageId == null || answer is! Map<String, dynamic>) return;
        _putAnswer(messageId, ChatPollResponse.fromJson(answer));
      case 'chat_poll_answers_changed':
        final messageId = (data['messageId'] as num?)?.toInt();
        if (messageId == null) return;
        _reloadAnswers(messageId).catchError((Object e) {
          debugPrint('[chat_messages_controller.dart] poll $messageId: $e');
        });
      case 'chat_poll_closed':
        final messageId = (data['messageId'] as num?)?.toInt();
        final poll = _messages[messageId]?.message.poll;
        if (messageId == null || poll == null) return;
        _changePoll(messageId, (poll) => poll.copyWith(closed: true));
        if (!poll.resultsAfterClose) return;
        _reloadAnswers(messageId).catchError((Object e) {
          debugPrint('[chat_messages_controller.dart] poll $messageId: $e');
        });
      case 'chat_channel_changed':
        _reloadEvents().then((_) => notifyListeners()).catchError((Object e) {
          debugPrint('[chat_messages_controller.dart] channel $channelId: $e');
        });
    }
  }

  static int _idOf(ChatTimelineEntry entry) => switch (entry) {
    ChatTimelineMessage(:final message) => message.id,
    ChatTimelineSystem(:final event) => event.id,
  };
}

/// One question's tally while [ChatMessagesController.pollItemFor] walks the
/// answers.
class _QuestionTally {
  _QuestionTally(this.question)
    : counts = List.filled(question.options.length, 0),
      ratings = List.filled(question.scale, 0);

  final ChatPollQuestion question;
  final List<int> counts;
  final List<String> texts = [];
  final List<int> ratings;
  ChatPollAnswer? mine;

  void add(ChatPollAnswer answer) {
    switch (question.type) {
      case ChatPollType.single || ChatPollType.multiple:
        for (final choice in answer.choices) {
          if (choice >= 0 && choice < counts.length) counts[choice]++;
        }
      case ChatPollType.text:
        texts.add(answer.text);
      case ChatPollType.number:
        final number = answer.number;
        if (number != null) texts.add(number);
      case ChatPollType.date:
        final date = answer.date;
        if (date != null) texts.add(date);
      case ChatPollType.rating:
        final rating = answer.rating;
        if (rating != null && rating >= 1 && rating <= ratings.length) {
          ratings[rating - 1]++;
        }
    }
  }

  ChatPollQuestionItem get item => ChatPollQuestionItem(
    prompt: question.prompt,
    type: question.type,
    options: question.options,
    counts: counts,
    textAnswers: List.unmodifiable(texts),
    scale: question.scale,
    ratingCounts: ratings,
    myAnswer: mine,
  );
}
