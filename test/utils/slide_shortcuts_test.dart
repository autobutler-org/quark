import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/slide_shortcuts.dart';

/// The slides shortcut table (#1168): no two shortcuts collide in one
/// context, keys are spelled per platform, search finds by name and keys, and
/// docs/slides-keyboard-shortcuts.md names every shortcut.
void main() {
  const platforms = [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.android,
  ];

  test('ids are unique', () {
    final ids = SlideShortcuts.all.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  for (final platform in platforms) {
    test('no combo is shared within a context on $platform', () {
      final seen = <String, String>{};
      for (final shortcut in SlideShortcuts.all) {
        for (final combo in shortcut.combosFor(platform)) {
          final contexts = shortcut.context == SlideShortcutContext.anywhere
              ? SlideShortcutContext.values
              : [shortcut.context];
          for (final context in contexts) {
            final key = '${context.name}:${combo.join('+')}';
            expect(
              seen[key],
              isNull,
              reason: '$key is both ${seen[key]} and ${shortcut.id}',
            );
            seen[key] = shortcut.id;
          }
        }
      }
    });
  }

  test('Cmd on macOS and iOS, Ctrl elsewhere', () {
    const redo = [SlideShortcuts.mod, SlideShortcuts.shift, 'Z'];
    expect(SlideShortcuts.comboText(redo, TargetPlatform.macOS), '⌘⇧Z');
    expect(SlideShortcuts.comboText(redo, TargetPlatform.iOS), '⌘⇧Z');
    expect(
      SlideShortcuts.comboText(redo, TargetPlatform.windows),
      'Ctrl+Shift+Z',
    );
    expect(
      SlideShortcuts.comboSpoken(redo, TargetPlatform.macOS),
      'Command Shift Z',
    );
    expect(
      SlideShortcuts.comboSpoken(redo, TargetPlatform.linux),
      'Control Shift Z',
    );
  });

  test('a Mac offers only the redo combo it handles', () {
    final redo = SlideShortcuts.all.firstWhere((s) => s.id == 'redo');
    expect(redo.combosFor(TargetPlatform.macOS), hasLength(1));
    expect(redo.combosFor(TargetPlatform.linux), hasLength(2));
  });

  test('every section has a shortcut', () {
    for (final section in SlideShortcutSection.values) {
      expect(
        SlideShortcuts.all.any((s) => s.section == section),
        isTrue,
        reason: section.label,
      );
    }
  });

  test('search matches name, section and keys, every word', () {
    List<String> ids(String q, [TargetPlatform p = TargetPlatform.linux]) => [
      for (final s in SlideShortcuts.search(q, p)) s.id,
    ];
    expect(ids(''), hasLength(SlideShortcuts.all.length));
    expect(ids('bold'), ['text_bold']);
    expect(ids('ARRANGE'), containsAll(['bring_forward', 'group']));
    expect(ids('ctrl shift z'), containsAll(['redo', 'text_redo']));
    expect(ids('⌘ ⇧ z', TargetPlatform.macOS), contains('redo'));
    expect(ids('zzzz'), isEmpty);
  });

  test('docs/slides-keyboard-shortcuts.md names every shortcut', () {
    final doc = File('docs/slides-keyboard-shortcuts.md').readAsStringSync();
    for (final shortcut in SlideShortcuts.all) {
      expect(doc, contains(shortcut.label), reason: shortcut.id);
    }
  });
}
