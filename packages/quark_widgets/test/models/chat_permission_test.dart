import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The chat permission model (#2415): the names match the Quark's, the
/// presets are exactly the sets the issue lists, and the helpers keep a set
/// coherent.
void main() {
  const read = ChatPermission.readMessages;
  const send = ChatPermission.sendMessages;
  const react = ChatPermission.addReactions;
  const delete = ChatPermission.deleteMessages;
  const channel = ChatPermission.manageChannel;
  const members = ChatPermission.manageMembers;
  const reactions = ChatPermission.manageReactions;

  test('every permission carries the name the Quark uses', () {
    expect(
      [for (final p in ChatPermission.values) p.id],
      [
        'read_messages',
        'send_messages',
        'add_reactions',
        'delete_messages',
        'manage_reactions',
        'manage_channel',
        'manage_members',
      ],
    );
    for (final p in ChatPermission.values) {
      expect(ChatPermission.byId(p.id), p);
    }
    expect(ChatPermission.byId('view_channel'), isNull);
  });

  test('each preset is its exact set', () {
    final want = {
      ChatPermissionPreset.viewer: {read},
      ChatPermissionPreset.member: {read, send, react},
      ChatPermissionPreset.moderator: {
        read,
        send,
        react,
        delete,
        reactions,
        members,
      },
      ChatPermissionPreset.owner: {
        read,
        send,
        react,
        delete,
        reactions,
        channel,
        members,
      },
    };
    for (final MapEntry(key: preset, value: set) in want.entries) {
      expect(preset.permissions, set, reason: preset.name);
      expect(ChatPermissionPreset.of(set), preset);
      expect(ChatPermissionPreset.labelOf(set), preset.label);
    }
  });

  test('a set that matches no preset is Custom', () {
    expect(ChatPermissionPreset.of({members}), isNull);
    expect(
      ChatPermissionPreset.labelOf({members}),
      ChatPermissionPreset.customLabel,
    );
  });

  test('only the message permissions need read_messages', () {
    expect(send.requires, {read});
    expect(react.requires, {read});
    expect(delete.requires, {read});
    expect(reactions.requires, {read});
    expect(read.requires, isEmpty);
    expect(channel.requires, isEmpty);
    expect(members.requires, isEmpty);
  });

  test('prerequisites follow what needs them', () {
    expect(ChatPermission.withPrerequisites({delete, members}), {
      read,
      delete,
      members,
    });
    expect(
      ChatPermission.withoutDependents(
        ChatPermissionPreset.owner.permissions,
        read,
      ),
      {channel, members},
    );
  });
}
