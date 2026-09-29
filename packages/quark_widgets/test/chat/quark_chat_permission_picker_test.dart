import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The permission picker (#2415, #2422): presets round-trip to their exact
/// sets, anything else reads as Custom, ticking and clearing keep the set
/// coherent, and nothing the caller doesn't hold can be granted.
void main() {
  const prefix = 'chat_permission';
  ValueKey<String> box(ChatPermission p) => ValueKey('${prefix}_${p.id}');
  ValueKey<String> chip(String name) => ValueKey('${prefix}_preset_$name');

  // The picker is as tall as its checklist; like the share sheet, the host
  // scrolls.
  Widget host(Widget picker) => SingleChildScrollView(child: picker);

  Future<void> tap(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
    await tester.tap(find.byKey(key));
    await tester.pump();
  }

  bool selected(WidgetTester tester, String name) =>
      tester.widget<ChoiceChip>(find.byKey(chip(name))).selected;

  bool? ticked(WidgetTester tester, ChatPermission p) =>
      tester.widget<CheckboxListTile>(find.byKey(box(p))).value;

  testBothViewports('a preset chip hands back its exact set', (
    tester,
    size,
  ) async {
    final changes = <Set<ChatPermission>>[];
    await pumpAt(
      tester,
      host(
        QuarkChatPermissionPicker(
          permissions: ChatPermissionPreset.viewer.permissions,
          onChanged: changes.add,
        ),
      ),
      size: size,
    );

    expect(selected(tester, 'viewer'), isTrue);
    expect(selected(tester, 'custom'), isFalse);
    for (final preset in ChatPermissionPreset.values) {
      await tap(tester, chip(preset.name));
    }

    expect(changes, [
      for (final preset in ChatPermissionPreset.values) preset.permissions,
    ]);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('a set matching no preset shows as Custom, open', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      host(
        QuarkChatPermissionPicker(
          permissions: const {ChatPermission.manageMembers},
          onChanged: (_) {},
        ),
      ),
      size: size,
    );

    expect(selected(tester, 'custom'), isTrue);
    for (final preset in ChatPermissionPreset.values) {
      expect(selected(tester, preset.name), isFalse);
    }
    expect(ticked(tester, ChatPermission.manageMembers), isTrue);
    expect(ticked(tester, ChatPermission.readMessages), isFalse);
    expect(find.byKey(const ValueKey('${prefix}_empty')), findsNothing);
  });

  testBothViewports('choosing Custom opens the checkboxes', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      host(
        QuarkChatPermissionPicker(
          permissions: ChatPermissionPreset.member.permissions,
          onChanged: (_) {},
        ),
      ),
      size: size,
    );
    expect(find.byKey(box(ChatPermission.sendMessages)), findsNothing);

    await tap(tester, chip('custom'));

    expect(find.byKey(box(ChatPermission.sendMessages)), findsOneWidget);
  });

  testBothViewports('clearing read_messages keeps only the management bits', (
    tester,
    size,
  ) async {
    final changes = <Set<ChatPermission>>[];
    await pumpAt(
      tester,
      host(
        QuarkChatPermissionPicker(
          permissions: ChatPermissionPreset.owner.permissions,
          onChanged: changes.add,
        ),
      ),
      size: size,
    );
    // Owner is a preset, so open the checkboxes first.
    await tap(tester, chip('custom'));
    await tap(tester, box(ChatPermission.readMessages));

    expect(changes.single, {
      ChatPermission.manageChannel,
      ChatPermission.manageMembers,
    });
  });

  testBothViewports('ticking send_messages ticks what it needs', (
    tester,
    size,
  ) async {
    final changes = <Set<ChatPermission>>[];
    await pumpAt(
      tester,
      host(
        QuarkChatPermissionPicker(
          permissions: const {ChatPermission.manageMembers},
          onChanged: changes.add,
        ),
      ),
      size: size,
    );

    await tap(tester, box(ChatPermission.sendMessages));

    expect(changes.single, {
      ChatPermission.readMessages,
      ChatPermission.sendMessages,
      ChatPermission.manageMembers,
    });
  });

  testBothViewports('an empty set says it removes rather than saves', (
    tester,
    size,
  ) async {
    final changes = <Set<ChatPermission>>[];
    await pumpAt(
      tester,
      host(
        QuarkChatPermissionPicker(
          permissions: const {ChatPermission.readMessages},
          onChanged: changes.add,
        ),
      ),
      size: size,
    );
    expect(find.byKey(const ValueKey('${prefix}_empty')), findsNothing);
    await tap(tester, chip('custom'));
    await tap(tester, box(ChatPermission.readMessages));
    expect(changes.single, isEmpty);

    await pumpAt(
      tester,
      host(
        QuarkChatPermissionPicker(
          permissions: const {},
          onChanged: changes.add,
        ),
      ),
      size: size,
    );
    expect(find.text(QuarkChatPermissionPicker.emptyHint), findsOneWidget);
  });

  testBothViewports('what the caller does not hold is disabled, with why', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      host(
        QuarkChatPermissionPicker(
          permissions: const {ChatPermission.readMessages},
          heldPermissions: ChatPermissionPreset.moderator.permissions,
          onChanged: (_) {},
        ),
      ),
      size: size,
    );
    await tap(tester, chip('custom'));

    final manage = tester.widget<CheckboxListTile>(
      find.byKey(box(ChatPermission.manageChannel)),
    );
    expect(manage.onChanged, isNull);
    expect(find.text(QuarkChatPermissionPicker.notHeldReason), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(find.byKey(chip('owner'))).onSelected,
      isNull,
    );
    expect(
      tester.widget<ChoiceChip>(find.byKey(chip('moderator'))).onSelected,
      isNotNull,
    );
  });

  testBothViewports('without onChanged nothing can be changed', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      host(
        const QuarkChatPermissionPicker(
          permissions: {ChatPermission.manageChannel},
        ),
      ),
      size: size,
    );

    expect(
      tester.widget<ChoiceChip>(find.byKey(chip('viewer'))).onSelected,
      isNull,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(box(ChatPermission.readMessages)),
          )
          .onChanged,
      isNull,
    );
  });
}
