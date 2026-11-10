import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark_icons/quark_icons.dart';

import '../layout/quark_bar_icon_button.dart';
import '../models/chat_permission.dart';
import '../theme/quark_tokens.dart';
import 'chat_mentions.dart';
import 'quark_mention_suggestions.dart';

/// The field under a message list where a message is written and sent.
///
/// The field grows with what is typed, up to [maxLines], then scrolls. On a
/// desktop, including a desktop browser, Enter sends and Shift+Enter starts a new line; on a
/// phone, Enter starts a new line and the send button sends. The send button
/// is there on every platform. Enter never sends while an input method is
/// still composing, since that Enter confirms the composition. What is sent is trimmed, a blank message is
/// never sent, and the field clears once [onSend] has been called.
/// [onAttach] is separate: it asks the caller to send a file, which may have
/// an empty caption. This field still refuses a blank message.
///
/// The field is replaced by a sentence saying why the user can't write, for
/// two reasons of the channel's own and one of the caller's, first match
/// wins:
///
/// - [permissions] lacks [ChatPermission.readMessages]: [notMemberReason],
///   for someone who manages the channel without being in the conversation.
/// - [permissions] lacks [ChatPermission.sendMessages]: [noSendReason], which
///   lasts until someone changes the user's permissions.
/// - [isWaitingForKey]: [waitingForKeyReason], which resolves itself once a
///   member shares the channel key. The caller explains the wait, and what
///   to do about it, with a `QuarkEncryptionNotice` above.
/// - [disabledReason], any other sentence the caller composes.
///
/// With [mentionNames], typing `@` at the start of a word opens a
/// `QuarkMentionSuggestions` above the field with the members whose names
/// start with what follows (#2623). A tap on one, or Tab, or Enter where
/// Enter sends, puts `@name` and a space in the text; the arrow keys move
/// through the list and Escape closes it until another `@` is typed. Every
/// `@name` in the field that names a member is drawn as a mention, so a
/// mention that will reach someone looks different from one that won't. What
/// is sent is still the plain text, `@name` included.
///
/// The text controller and focus node are [State] because Flutter needs them
/// to live across rebuilds, as is where the keyboard is in the suggestions;
/// the outcome leaves through [onSend].
///
/// Key prefixes: `message_composer_field` on the text field,
/// `message_composer_attach` on the attach button, shown when [onAttach]
/// is set and [permissions] allows [ChatPermission.attachFiles] (or
/// [permissions] is null),
/// `message_composer_send` on the send button,
/// `message_composer_disabled` on the disabled sentence, and those of
/// `QuarkMentionSuggestions`.
///
/// ```dart
/// QuarkMessageComposer(
///   hintText: 'Message #general',
///   permissions: controller.selectedPermissions,
///   isWaitingForKey: controller.isWaitingForKey,
///   mentionNames: controller.mentionNames,
///   onSend: controller.send,
/// );
/// ```
class QuarkMessageComposer extends StatefulWidget {
  /// Creates a composer that hands what is written to [onSend].
  const QuarkMessageComposer({
    required this.onSend,
    this.initialText = '',
    this.onChanged,
    this.hintText = 'Message',
    this.permissions,
    this.isWaitingForKey = false,
    this.disabledReason,
    this.maxLines = 6,
    this.maxLength,
    this.mentionNames = const [],
    this.onAttach,
    super.key,
  });

  /// Called with the trimmed text when the user sends a message that is not
  /// blank.
  final ValueChanged<String> onSend;

  /// Text already written, shown when the composer is created. A later
  /// change to this value does not replace what is in the field; the caller
  /// gives each channel its own composer.
  final String initialText;

  /// Called with the field's text each time it changes, including when a
  /// send clears it. Restoring [initialText] does not call this.
  final ValueChanged<String>? onChanged;

  /// The placeholder in the empty field.
  final String hintText;

  /// What the user may do in the channel. Without
  /// [ChatPermission.sendMessages] the field is replaced by [noSendReason].
  /// Null doesn't check.
  final Set<ChatPermission>? permissions;

  /// Whether the user is waiting for a member to share the channel key, which
  /// replaces the field with [waitingForKeyReason].
  final bool isWaitingForKey;

  /// Any other reason the user cannot write here, composed by the caller.
  /// Non-null shows this sentence in place of the field.
  final String? disabledReason;

  /// Shown to a user without [ChatPermission.readMessages].
  static const String notMemberReason =
      'You are not a member of this conversation';

  /// Shown to a user without [ChatPermission.sendMessages].
  static const String noSendReason =
      'You can read this channel but not send messages in it';

  /// Shown while the user waits for the channel key.
  static const String waitingForKeyReason =
      "You can write here once a member shares this channel's key with you";

  /// How many lines the field grows to before it scrolls.
  final int maxLines;

  /// The longest message that sends, in UTF-16 code units as
  /// [String.length] counts them, measured on the trimmed text. Null has no
  /// limit.
  ///
  /// Within a tenth of it, a counter under the field says how much is left,
  /// key `message_composer_counter`. Past it, the counter gives way to
  /// [overLimitText], key `message_composer_too_long`, the send button turns
  /// off with [tooLongText] as its tooltip, and Enter keeps the draft rather
  /// than sending it.
  final int? maxLength;

  /// The names an `@mention` can resolve to, usually the channel's members,
  /// in the order to suggest them. Empty suggests and styles nothing.
  final List<String> mentionNames;

  /// Called when the attach button is pressed. The button does not pick a
  /// file; the caller does. Null hides the button. A non-null callback still
  /// hides it when [permissions] is set and lacks [ChatPermission.attachFiles].
  /// Null [permissions] shows it, the same way null [permissions] leaves send
  /// unchecked.
  final VoidCallback? onAttach;

  /// Said when Enter is pressed on a blank message, under the field with key
  /// `message_composer_hint`, and as the turned-off send button's tooltip.
  static const String blankHint = 'Type a message to send';

  /// The send button's tooltip when the message is longer than [maxLength].
  static const String tooLongText = 'This message is too long to send';

  /// Said under the field when the message is [count] code units longer than
  /// [maxLength].
  static String overLimitText(int count) =>
      '$count characters over the limit. Shorten it to send.';

  @override
  State<QuarkMessageComposer> createState() => _QuarkMessageComposerState();
}

class _QuarkMessageComposerState extends State<QuarkMessageComposer> {
  late final _MentionTextController _text = _MentionTextController()
    ..names = widget.mentionNames;
  final FocusNode _focus = FocusNode();

  /// Whether Enter was pressed on a blank message; typing anything clears it.
  bool _showBlankHint = false;

  /// The suggestion the keyboard is on; typing puts it back on the first.
  int _highlight = 0;

  /// Where the `@` sits whose suggestions Escape closed. They stay closed
  /// until the caret leaves that mention.
  int? _dismissedAt;

  String _lastText = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialText;
    if (initial.isNotEmpty) {
      _text.value = TextEditingValue(
        text: initial,
        selection: TextSelection.collapsed(offset: initial.length),
      );
      _lastText = initial;
    }
    _text.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(QuarkMessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _text.names = widget.mentionNames;
  }

  void _onTextChanged() {
    if (_text.text != _lastText) {
      _lastText = _text.text;
      _highlight = 0;
      widget.onChanged?.call(_text.text);
    }
    if (ChatMentions.queryAt(_text.text, _text.selection.baseOffset) == null) {
      _dismissedAt = null;
    }
    if (_showBlankHint && _text.text.trim().isNotEmpty) {
      setState(() => _showBlankHint = false);
    }
  }

  /// The mention being typed at the caret and the names to offer for it, or
  /// null when there is nothing to suggest.
  ({int start, List<String> names})? _suggestions() {
    final selection = _text.selection;
    if (widget.mentionNames.isEmpty ||
        !selection.isValid ||
        !selection.isCollapsed) {
      return null;
    }
    final query = ChatMentions.queryAt(_text.text, selection.baseOffset);
    if (query == null || query.start == _dismissedAt) return null;
    final names = ChatMentions.matching(widget.mentionNames, query.query);
    return names.isEmpty ? null : (start: query.start, names: names);
  }

  /// Replaces the mention being typed, from the `@` at [start] to the caret,
  /// with `@name` and a space.
  void _mention(int start, String name) {
    final text = _text.text;
    final head = '${text.substring(0, start)}@$name ';
    _text.value = TextEditingValue(
      text: '$head${text.substring(_text.selection.baseOffset)}',
      selection: TextSelection.collapsed(offset: head.length),
    );
    _focus.requestFocus();
  }

  /// How many code units the trimmed text is over [maxLength], negative
  /// when under, and null with no limit.
  int? _overBy(String message) {
    final max = widget.maxLength;
    return max == null ? null : message.length - max;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _sendFromEnter() {
    // An input method (Japanese, Chinese, Korean) uses Enter to confirm what
    // it is composing; that Enter is not a send. The send button still sends,
    // since a phone keyboard keeps a composing region while plain typing.
    if (_text.value.composing.isValid) return;
    _send();
  }

  /// Inserts a newline at the caret. Does nothing while an input method is
  /// composing, the same way [_sendFromEnter] does.
  void _insertNewline() {
    if (_text.value.composing.isValid) return;
    final text = _text.text;
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _text.value = TextEditingValue(
      text: '${text.substring(0, start)}\n${text.substring(end)}',
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  /// One hardware Enter on the web is delivered twice: the key event, then
  /// the field's input action. The second one has to be ignored, or a send
  /// is followed by the blank hint and Shift+Enter sends the line it just
  /// broke.
  bool _enterHandled = false;

  void _once(VoidCallback action) {
    if (_enterHandled) return;
    _enterHandled = true;
    Future.microtask(() {
      if (mounted) _enterHandled = false;
    });
    action();
  }

  void _send() {
    final message = _text.text.trim();
    if (message.isEmpty) {
      // Enter on a blank message used to do nothing at all (#2502).
      setState(() => _showBlankHint = true);
      return;
    }
    if ((_overBy(message) ?? 0) > 0) return;
    widget.onSend(message);
    _text.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final permissions = widget.permissions;
    final reason = permissions == null
        ? null
        : !permissions.contains(ChatPermission.readMessages)
        ? QuarkMessageComposer.notMemberReason
        : !permissions.contains(ChatPermission.sendMessages)
        ? QuarkMessageComposer.noSendReason
        : null;
    final shown =
        reason ??
        (widget.isWaitingForKey
            ? QuarkMessageComposer.waitingForKeyReason
            : widget.disabledReason);

    if (shown != null) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: Row(
          key: const ValueKey('message_composer_disabled'),
          children: [
            Icon(
              QuarkIcons.lock_outline,
              size: 18,
              color: tokens.mutedForeground,
            ),
            SizedBox(width: tokens.spacingSm),
            Expanded(
              child: Text(
                shown,
                style: TextStyle(color: tokens.mutedForeground),
              ),
            ),
          ],
        ),
      );
    }

    // Horizontal only. Vertical padding here would drop the attach button
    // below the poll button, which sits outside this composer.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tokens.spacingSm),
      child: ListenableBuilder(
        listenable: _text,
        builder: (context, _) {
          final message = _text.text.trim();
          final overBy = _overBy(message);
          final max = widget.maxLength;
          // One line under the field: on a phone, an error beside a counter
          // squeezes the error into a column a word wide.
          final over = overBy != null && overBy > 0;
          final counter = over || max == null || -overBy! > max ~/ 10
              ? null
              : '${-overBy} characters left';
          WidgetStateProperty<T?> disabledOr<T>(T disabled, [T? enabled]) =>
              WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.disabled) ? disabled : enabled,
              );
          final sendReason = message.isEmpty
              ? QuarkMessageComposer.blankHint
              : over
              ? QuarkMessageComposer.tooLongText
              : null;

          final suggestions = _suggestions();
          final highlighted = suggestions == null
              ? null
              : suggestions.names[_highlight % suggestions.names.length];
          void pick() {
            // As in _sendFromEnter: this Enter belongs to the input method.
            if (_text.value.composing.isValid) return;
            _mention(suggestions!.start, highlighted!);
          }

          final onEnter = suggestions == null ? _sendFromEnter : pick;
          // Hardware Enter sends on every platform. Shift+Enter inserts a
          // newline. The on-screen keyboard's action is Send, and it takes
          // the same path.
          void onEnterKey({required bool shift}) => _once(() {
            if (shift) {
              _insertNewline();
            } else {
              onEnter();
            }
          });

          final canAttach =
              widget.onAttach != null &&
              (permissions == null ||
                  permissions.contains(ChatPermission.attachFiles));
          // A tap outside a field closes the keyboard (#4051). The send
          // button, the attach button and a mention are part of the field,
          // so tapping one does not close it only for [_send] to reopen it.
          return TextFieldTapRegion(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (suggestions != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: tokens.spacingSm),
                    child: QuarkMentionSuggestions(
                      names: suggestions.names,
                      highlighted: highlighted,
                      onSelect: (name) => _mention(suggestions.start, name),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (canAttach) ...[
                      QuarkBarIconButton(
                        key: const ValueKey('message_composer_attach'),
                        icon: QuarkIcons.attach_file,
                        tooltip: 'Attach a file',
                        onPressed: widget.onAttach,
                      ),
                      SizedBox(width: tokens.spacingSm),
                    ],
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: {
                          if (suggestions != null) ...{
                            const SingleActivator(
                              LogicalKeyboardKey.arrowDown,
                            ): () =>
                                setState(() => _highlight++),
                            const SingleActivator(
                              LogicalKeyboardKey.arrowUp,
                            ): () =>
                                setState(() => _highlight--),
                            const SingleActivator(LogicalKeyboardKey.tab): pick,
                            const SingleActivator(
                              LogicalKeyboardKey.escape,
                            ): () => setState(
                              () => _dismissedAt = suggestions.start,
                            ),
                          },
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            shift: true,
                          ): () =>
                              onEnterKey(shift: true),
                          const SingleActivator(
                            LogicalKeyboardKey.numpadEnter,
                            shift: true,
                          ): () =>
                              onEnterKey(shift: true),
                          const SingleActivator(LogicalKeyboardKey.enter): () =>
                              onEnterKey(shift: false),
                          const SingleActivator(
                            LogicalKeyboardKey.numpadEnter,
                          ): () =>
                              onEnterKey(shift: false),
                        },
                        child: TextField(
                          key: const ValueKey('message_composer_field'),
                          controller: _text,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: widget.maxLines,
                          keyboardType: TextInputType.multiline,
                          // Send's default drops focus. The caret stays so the
                          // next message can be typed.
                          onEditingComplete: () => _focus.requestFocus(),
                          onSubmitted: (_) => onEnterKey(
                            shift: HardwareKeyboard.instance.isShiftPressed,
                          ),
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: widget.hintText,
                            helper: _showBlankHint
                                ? const Text(
                                    QuarkMessageComposer.blankHint,
                                    key: ValueKey('message_composer_hint'),
                                  )
                                : null,
                            error: over
                                ? Text(
                                    QuarkMessageComposer.overLimitText(overBy),
                                    key: const ValueKey(
                                      'message_composer_too_long',
                                    ),
                                  )
                                : null,
                            counter: counter == null
                                ? null
                                : Text(
                                    counter,
                                    key: const ValueKey(
                                      'message_composer_counter',
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: tokens.spacingSm),
                    IconButton.filled(
                      key: const ValueKey('message_composer_send'),
                      tooltip: sendReason ?? 'Send',
                      icon: const Icon(QuarkIcons.send_rounded),
                      // The theme's icon color overrode the filled button's
                      // own, a slate glyph on the accent at 1.4:1 in dark mode,
                      // so the glyph is the accent's foreground. Material's
                      // disabled fill, the text color at 12%, all but vanished
                      // on a dark page, and the composer is empty most of the
                      // time: disabled, it is an input outlined in
                      // [QuarkTokens.outline] with a muted glyph, unlike the
                      // filled button but 3:1 (#3257).
                      style: ButtonStyle(
                        backgroundColor: disabledOr(tokens.input),
                        foregroundColor: disabledOr(
                          tokens.mutedForeground,
                          tokens.primaryForeground,
                        ),
                        side: disabledOr(BorderSide(color: tokens.outline)),
                      ),
                      onPressed: sendReason == null ? _send : null,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The composer's text, with each `@name` that names one of [names] drawn as
/// a mention. Only how the text is painted changes; [text] stays as typed.
class _MentionTextController extends TextEditingController {
  /// The names a mention can resolve to.
  List<String> names = const [];

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final mentions = ChatMentions.mentionsIn(text, names);
    if (mentions.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final mentionStyle = ChatMentions.styleOf(QuarkTokens.of(context));
    // The input method's underline, which the default span draws, has to
    // survive beside the mentions: a phone keyboard composes while typing.
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final cuts = {
      0,
      text.length,
      for (final mention in mentions) ...[mention.start, mention.end],
      if (composing.isValid) ...[composing.start, composing.end],
    }.toList()..sort();
    return TextSpan(
      style: style,
      children: [
        for (final (index, start) in cuts.indexed.take(cuts.length - 1))
          TextSpan(
            text: text.substring(start, cuts[index + 1]),
            style:
                (mentions.any((m) => m.start <= start && start < m.end)
                        ? mentionStyle
                        : const TextStyle())
                    .merge(
                      composing.start <= start && start < composing.end
                          ? const TextStyle(
                              decoration: TextDecoration.underline,
                            )
                          : null,
                    ),
          ),
      ],
    );
  }
}
