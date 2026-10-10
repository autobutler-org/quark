import 'package:quark_widgets/quark_widgets.dart';

/// The fake channels the chat entries share: two open, one private with
/// unread messages.
const List<ChatChannelItem> galleryChatChannels = [
  ChatChannelItem(id: 'general', name: 'general'),
  ChatChannelItem(
    id: 'family',
    name: 'family',
    isPrivate: true,
    unreadCount: 3,
  ),
  ChatChannelItem(id: 'book-club', name: 'book-club'),
];

/// The fake members the chat entries share: an owner, a group of members, a
/// viewer, and a delegated manager with a custom set.
final List<ChatMemberItem> galleryChatMembers = [
  ChatMemberItem(
    id: 'ada',
    name: 'Ada Lovelace',
    permissions: ChatPermissionPreset.owner.permissions,
  ),
  ChatMemberItem(
    id: 'family',
    name: 'Family',
    isGroup: true,
    permissions: ChatPermissionPreset.member.permissions,
    members: const [
      ChatMemberItem(id: 'bob', name: 'Bob Byron'),
      ChatMemberItem(id: 'cy', name: 'Cy'),
    ],
  ),
  ChatMemberItem(
    id: 'dee',
    name: 'Dee',
    permissions: ChatPermissionPreset.viewer.permissions,
  ),
  const ChatMemberItem(
    id: 'eve',
    name: 'Eve',
    permissions: {ChatPermission.manageMembers},
  ),
];

/// The signed-in account in the chat entries, which wrote some of
/// [galleryChatMessages].
const String galleryChatUserId = 'bob';

/// The fake messages the chat entries share, newest first: two days, a run
/// from one author, a system line, an unverified one, a message waiting for
/// its key, a deleted one, and one with reactions.
final List<ChatMessageItem> galleryChatMessages = [
  ChatMessageItem(
    id: 'm8',
    authorId: 'ada',
    authorName: 'Ada Lovelace',
    sentAt: DateTime(2026, 9, 24, 9, 30),
    kind: ChatMessageKind.deleted,
  ),
  ChatMessageItem(
    id: 'm7',
    authorId: 'bob',
    authorName: 'Bob Byron',
    sentAt: DateTime(2026, 9, 24, 9, 12),
    kind: ChatMessageKind.waitingForKey,
  ),
  ChatMessageItem(
    id: 'm6',
    authorId: 'bob',
    authorName: 'Bob Byron',
    sentAt: DateTime(2026, 9, 24, 9, 10),
    body:
        'Morning! Is anyone bringing the projector? The manual is at '
        'https://example.com/projector/manual (page 4), or www.example.org.',
  ),
  ChatMessageItem(
    id: 'm5',
    authorId: 'eve',
    authorName: 'Eve',
    sentAt: DateTime(2026, 9, 24, 9, 5),
    kind: ChatMessageKind.system,
    body: 'Eve joined the channel',
    isUnverified: true,
  ),
  ChatMessageItem(
    id: 'm4',
    authorId: 'ada',
    authorName: 'Ada Lovelace',
    sentAt: DateTime(2026, 9, 24, 9),
    kind: ChatMessageKind.system,
    body: 'Ada made a new key for this channel',
    isEncryptionEvent: true,
  ),
  ChatMessageItem(
    id: 'm3',
    authorId: 'ada',
    authorName: 'Ada Lovelace',
    sentAt: DateTime(2026, 9, 23, 20, 2),
    body: 'I will bring the snacks.',
    reactions: const [
      ChatReactionItem(emoji: '🎉', count: 2, reactedByMe: true),
      ChatReactionItem(emoji: '👍', count: 1),
    ],
  ),
  ChatMessageItem(
    id: 'm2',
    authorId: 'ada',
    authorName: 'Ada Lovelace',
    sentAt: DateTime(2026, 9, 23, 20, 1),
    body: 'Book club is at mine on Thursday.',
  ),
  ChatMessageItem(
    id: 'm1',
    authorId: 'bob',
    authorName: 'Bob Byron',
    sentAt: DateTime(2026, 9, 23, 19, 55),
    body: 'Where are we meeting this week?',
  ),
];
