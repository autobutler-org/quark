import 'package:flutter/foundation.dart';

/// Where in the slides app a shortcut is live. Two shortcuts may share a
/// combination only when their contexts differ: Escape deselects on the
/// canvas, finishes a text edit, and ends a show.
enum SlideShortcutContext {
  /// The editor, focus on the canvas or its panels, no text box open.
  canvas,

  /// A text box being edited.
  textEdit,

  /// A running presentation.
  present,

  /// Everywhere in the editor, text boxes included.
  anywhere,
}

/// The sections the help dialog groups shortcuts under, in display order.
enum SlideShortcutSection {
  /// Changing the slide: undo, redo, delete, nudge.
  editing('Editing'),

  /// Choosing elements.
  selection('Selection'),

  /// Typing inside a text box.
  text('Text'),

  /// Stacking order.
  arrange('Arrange'),

  /// Looking at the editor, and asking for help.
  view('View'),

  /// Running the show.
  present('Present');

  const SlideShortcutSection(this.label);

  /// The heading shown in the dialog.
  final String label;
}

/// One keyboard shortcut of the slides app: what it does and the key
/// combinations that do it.
///
/// A combination is a list of key names pressed together. [mod] stands for
/// Cmd on macOS and iOS and Ctrl elsewhere, so one entry serves every
/// platform; [macCombos] replaces [combos] where a Mac differs.
@immutable
class SlideShortcut {
  /// A shortcut that runs [id], shown as [label] under [section].
  const SlideShortcut({
    required this.id,
    required this.label,
    required this.section,
    required this.context,
    required this.combos,
    this.macCombos,
  });

  /// Stable name, also the suffix of the row's `ValueKey`.
  final String id;

  /// What the shortcut does, as a short imperative phrase.
  final String label;

  /// The dialog section it is listed under.
  final SlideShortcutSection section;

  /// Where it is live.
  final SlideShortcutContext context;

  /// Alternative key combinations, each a list of keys held together. Any
  /// one does the job.
  final List<List<String>> combos;

  /// Replacement for [combos] on macOS and iOS; null when they match.
  final List<List<String>>? macCombos;

  /// The combinations on [platform], with [mod] still unresolved.
  List<List<String>> combosFor(TargetPlatform platform) =>
      (SlideShortcuts.usesCommand(platform) ? macCombos : null) ?? combos;
}

/// The single source of truth for the slides keyboard shortcuts: the help
/// dialog renders it, `docs/slides-keyboard-shortcuts.md` documents it, and a
/// test keeps the two in step. Add a shortcut to the code that handles it
/// and to [all] together.
abstract final class SlideShortcuts {
  /// The key name that means Cmd on macOS and iOS, Ctrl elsewhere.
  static const String mod = 'Mod';

  /// The Shift key.
  static const String shift = 'Shift';

  /// The Alt key, Option on a Mac.
  static const String alt = 'Alt';

  /// Whether [platform] spells its command key Cmd.
  static bool usesCommand(TargetPlatform platform) =>
      platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

  /// The legend for one key on [platform], as printed on a key cap.
  static String keyLabel(String key, TargetPlatform platform) {
    final mac = usesCommand(platform);
    return switch (key) {
      mod => mac ? '⌘' : 'Ctrl',
      shift => mac ? '⇧' : 'Shift',
      alt => mac ? '⌥' : 'Alt',
      'Backspace' when mac => '⌫',
      _ => key,
    };
  }

  /// One key as a screen reader should say it on [platform].
  static String spokenKey(String key, TargetPlatform platform) {
    final mac = usesCommand(platform);
    return switch (key) {
      mod => mac ? 'Command' : 'Control',
      alt => mac ? 'Option' : 'Alt',
      '←' => 'Left arrow',
      '→' => 'Right arrow',
      '↑' => 'Up arrow',
      '↓' => 'Down arrow',
      ']' => 'Right bracket',
      '[' => 'Left bracket',
      '?' => 'Question mark',
      _ => key,
    };
  }

  /// The caps of one combination on [platform], in press order.
  static List<String> capsFor(List<String> combo, TargetPlatform platform) => [
    for (final key in combo) keyLabel(key, platform),
  ];

  /// A combination as plain text, such as `Ctrl+Shift+Z` or `⌘⇧Z`.
  static String comboText(List<String> combo, TargetPlatform platform) =>
      capsFor(combo, platform).join(usesCommand(platform) ? '' : '+');

  /// A combination as a screen reader should say it.
  static String comboSpoken(List<String> combo, TargetPlatform platform) =>
      [for (final key in combo) spokenKey(key, platform)].join(' ');

  /// The shortcuts whose label, section or keys on [platform] contain every
  /// word of [query], in table order; all of them for a blank query.
  static List<SlideShortcut> search(String query, TargetPlatform platform) {
    final words = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return all;
    return [
      for (final shortcut in all)
        if (words.every(_haystack(shortcut, platform).contains)) shortcut,
    ];
  }

  static String _haystack(SlideShortcut shortcut, TargetPlatform platform) => [
    shortcut.label,
    shortcut.section.label,
    for (final combo in shortcut.combosFor(platform)) ...[
      comboText(combo, platform),
      comboSpoken(combo, platform),
    ],
  ].join(' ').toLowerCase();

  /// Every shortcut, grouped by section in display order.
  static const List<SlideShortcut> all = [
    SlideShortcut(
      id: 'undo',
      label: 'Undo',
      section: SlideShortcutSection.editing,
      context: SlideShortcutContext.canvas,
      combos: [
        [mod, 'Z'],
      ],
    ),
    SlideShortcut(
      id: 'redo',
      label: 'Redo',
      section: SlideShortcutSection.editing,
      context: SlideShortcutContext.canvas,
      combos: [
        [mod, shift, 'Z'],
        [mod, 'Y'],
      ],
      macCombos: [
        [mod, shift, 'Z'],
      ],
    ),
    SlideShortcut(
      id: 'delete',
      label: 'Delete the selection',
      section: SlideShortcutSection.editing,
      context: SlideShortcutContext.canvas,
      combos: [
        ['Delete'],
        ['Backspace'],
      ],
    ),
    SlideShortcut(
      id: 'nudge',
      label: 'Nudge the selection 1 unit',
      section: SlideShortcutSection.editing,
      context: SlideShortcutContext.canvas,
      combos: [
        ['Arrow keys'],
      ],
    ),
    SlideShortcut(
      id: 'nudge_far',
      label: 'Nudge the selection 10 units',
      section: SlideShortcutSection.editing,
      context: SlideShortcutContext.canvas,
      combos: [
        [shift, 'Arrow keys'],
      ],
    ),
    SlideShortcut(
      id: 'copy',
      label: 'Copy the selection',
      section: SlideShortcutSection.editing,
      context: SlideShortcutContext.canvas,
      combos: [
        [mod, 'C'],
      ],
    ),
    SlideShortcut(
      id: 'cut',
      label: 'Cut the selection',
      section: SlideShortcutSection.editing,
      context: SlideShortcutContext.canvas,
      combos: [
        [mod, 'X'],
      ],
    ),
    SlideShortcut(
      id: 'paste',
      label: 'Paste',
      section: SlideShortcutSection.editing,
      context: SlideShortcutContext.canvas,
      combos: [
        [mod, 'V'],
      ],
    ),
    SlideShortcut(
      id: 'duplicate',
      label: 'Duplicate the selection',
      section: SlideShortcutSection.editing,
      context: SlideShortcutContext.canvas,
      combos: [
        [mod, 'D'],
      ],
    ),
    SlideShortcut(
      id: 'edit_text',
      label: 'Edit the selected text box',
      section: SlideShortcutSection.editing,
      context: SlideShortcutContext.canvas,
      combos: [
        ['Enter'],
        ['F2'],
      ],
    ),
    SlideShortcut(
      id: 'next_element',
      label: 'Select the next element',
      section: SlideShortcutSection.selection,
      context: SlideShortcutContext.canvas,
      combos: [
        ['Tab'],
      ],
    ),
    SlideShortcut(
      id: 'previous_element',
      label: 'Select the previous element',
      section: SlideShortcutSection.selection,
      context: SlideShortcutContext.canvas,
      combos: [
        [shift, 'Tab'],
      ],
    ),
    SlideShortcut(
      id: 'deselect',
      label: 'Clear the selection',
      section: SlideShortcutSection.selection,
      context: SlideShortcutContext.canvas,
      combos: [
        ['Esc'],
      ],
    ),
    SlideShortcut(
      id: 'text_done',
      label: 'Finish editing the text box',
      section: SlideShortcutSection.text,
      context: SlideShortcutContext.textEdit,
      combos: [
        ['Esc'],
      ],
    ),
    SlideShortcut(
      id: 'text_bold',
      label: 'Bold',
      section: SlideShortcutSection.text,
      context: SlideShortcutContext.textEdit,
      combos: [
        [mod, 'B'],
      ],
    ),
    SlideShortcut(
      id: 'text_italic',
      label: 'Italic',
      section: SlideShortcutSection.text,
      context: SlideShortcutContext.textEdit,
      combos: [
        [mod, 'I'],
      ],
    ),
    SlideShortcut(
      id: 'text_underline',
      label: 'Underline',
      section: SlideShortcutSection.text,
      context: SlideShortcutContext.textEdit,
      combos: [
        [mod, 'U'],
      ],
    ),
    SlideShortcut(
      id: 'text_select_all',
      label: 'Select all text in the box',
      section: SlideShortcutSection.text,
      context: SlideShortcutContext.textEdit,
      combos: [
        [mod, 'A'],
      ],
    ),
    SlideShortcut(
      id: 'text_undo',
      label: 'Undo typing',
      section: SlideShortcutSection.text,
      context: SlideShortcutContext.textEdit,
      combos: [
        [mod, 'Z'],
      ],
    ),
    SlideShortcut(
      id: 'text_redo',
      label: 'Redo typing',
      section: SlideShortcutSection.text,
      context: SlideShortcutContext.textEdit,
      combos: [
        [mod, shift, 'Z'],
        [mod, 'Y'],
      ],
    ),
    SlideShortcut(
      id: 'bring_forward',
      label: 'Bring forward',
      section: SlideShortcutSection.arrange,
      context: SlideShortcutContext.canvas,
      combos: [
        [mod, ']'],
      ],
    ),
    SlideShortcut(
      id: 'send_backward',
      label: 'Send backward',
      section: SlideShortcutSection.arrange,
      context: SlideShortcutContext.canvas,
      combos: [
        [mod, '['],
      ],
    ),
    SlideShortcut(
      id: 'bring_to_front',
      label: 'Bring to front',
      section: SlideShortcutSection.arrange,
      context: SlideShortcutContext.canvas,
      combos: [
        [mod, shift, ']'],
      ],
    ),
    SlideShortcut(
      id: 'send_to_back',
      label: 'Send to back',
      section: SlideShortcutSection.arrange,
      context: SlideShortcutContext.canvas,
      combos: [
        [mod, shift, '['],
      ],
    ),
    SlideShortcut(
      id: 'group',
      label: 'Group the selection',
      section: SlideShortcutSection.arrange,
      context: SlideShortcutContext.canvas,
      combos: [
        [mod, 'G'],
      ],
    ),
    SlideShortcut(
      id: 'ungroup',
      label: 'Ungroup the selection',
      section: SlideShortcutSection.arrange,
      context: SlideShortcutContext.canvas,
      combos: [
        [mod, shift, 'G'],
      ],
    ),
    SlideShortcut(
      id: 'help',
      label: 'Show keyboard shortcuts',
      section: SlideShortcutSection.view,
      context: SlideShortcutContext.anywhere,
      combos: [
        ['?'],
        ['F1'],
      ],
    ),
    SlideShortcut(
      id: 'present_next',
      label: 'Next slide',
      section: SlideShortcutSection.present,
      context: SlideShortcutContext.present,
      combos: [
        ['→'],
        ['Space'],
        ['Page Down'],
        ['Enter'],
      ],
    ),
    SlideShortcut(
      id: 'present_previous',
      label: 'Previous slide',
      section: SlideShortcutSection.present,
      context: SlideShortcutContext.present,
      combos: [
        ['←'],
        ['Page Up'],
        ['Backspace'],
      ],
    ),
    SlideShortcut(
      id: 'present_first',
      label: 'First slide',
      section: SlideShortcutSection.present,
      context: SlideShortcutContext.present,
      combos: [
        ['Home'],
      ],
    ),
    SlideShortcut(
      id: 'present_last',
      label: 'Last slide',
      section: SlideShortcutSection.present,
      context: SlideShortcutContext.present,
      combos: [
        ['End'],
      ],
    ),
    SlideShortcut(
      id: 'present_fullscreen',
      label: 'Toggle fullscreen',
      section: SlideShortcutSection.present,
      context: SlideShortcutContext.present,
      combos: [
        ['F'],
      ],
    ),
    SlideShortcut(
      id: 'present_exit',
      label: 'End the show',
      section: SlideShortcutSection.present,
      context: SlideShortcutContext.present,
      combos: [
        ['Esc'],
      ],
    ),
  ];
}
