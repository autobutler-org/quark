import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../models/quark_menu_entry.dart';
import '../../../theme/quark_tokens.dart';
import '../../../theme/reduce_motion.dart';
import 'chat_context_menu_actions.dart';
import 'chat_context_menu_layout.dart';
import 'chat_quick_reaction_bar.dart';

/// Opens [ChatMessageContextMenu] for the message row at [context], over
/// everything on the root navigator, and runs the chosen action once it has
/// closed.
///
/// The row's rect becomes the menu's anchor. The route takes no focus, so a
/// keyboard that is up stays up under the menu, and the menu fits above it.
/// A tap outside the parts, or the system back gesture, closes it with
/// nothing chosen. Reduced motion is read here, from [context], once: the
/// menu lives for one gesture.
Future<void> showChatMessageContextMenu(
  BuildContext context, {
  required String messageId,
  required Widget copy,
  required List<QuarkMenuEntry> entries,
  double indent = 0,
  ValueChanged<String>? onReact,
  VoidCallback? onMoreEmoji,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final row = context.findRenderObject()! as RenderBox;
  final anchor = row.localToGlobal(Offset.zero, ancestor: overlay) & row.size;
  final reduceMotion = reduceMotionOf(context);
  final picked = await navigator.push(
    RawDialogRoute<VoidCallback>(
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      // Taking focus would close the keyboard under a message the reader
      // may be about to quote or answer.
      requestFocus: false,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, _) => ChatMessageContextMenu(
        messageId: messageId,
        anchor: anchor,
        indent: indent,
        copy: copy,
        entries: entries,
        animation: animation,
        reduceMotion: reduceMotion,
        onReact: onReact,
        onMoreEmoji: onMoreEmoji,
        onSelected: (run) => Navigator.pop(context, run),
      ),
    ),
  );
  picked?.call();
}

/// A message's actions on a touch screen, shown on a long press: the
/// message lifted out of the list over a blurred, dimmed page, a
/// `ChatQuickReactionBar` above it and a `ChatContextMenuActions` list
/// under it, as Signal and iOS do.
///
/// [copy] is drawn at [anchor], the original row's rect, on a card, and
/// does not take touches. `ChatContextMenuLayout` moves it as little as it
/// can so that the bar, the copy and every one of [entries] fit between the
/// safe area and the keyboard; a message too tall for that scrolls inside
/// its card. The bar is there only with [onReact].
///
/// Every choice goes out through [onSelected]: an entry's `onSelected`, a
/// call of [onReact] with the emoji, or [onMoreEmoji]. The caller closes the
/// menu and then runs it, which is what [showChatMessageContextMenu] does.
///
/// The copy lifts in on [animation], scaling up a little over a shadow,
/// while the route fades the rest in. Under [reduceMotion] the lift and its
/// shadow are dropped and the copy stands still in place; the fade stays.
/// The blur and the dim are not motion and stay too.
///
/// A part of `ChatMessageRow`, tested through `QuarkMessageList`.
///
/// Key prefixes: `message_context_copy_<messageId>` on the copy's card,
/// `message_context_lift_<messageId>` on its lift (absent under reduced
/// motion), and those of `ChatQuickReactionBar` and of [entries].
///
/// ```dart
/// showChatMessageContextMenu(
///   context,
///   messageId: message.id,
///   copy: IgnorePointer(child: rowCopy),
///   entries: [QuarkMenuEntry(label: 'Copy text', onSelected: copy)],
///   onReact: react,
/// );
/// ```
class ChatMessageContextMenu extends StatelessWidget {
  /// Creates the menu for message [messageId].
  const ChatMessageContextMenu({
    required this.messageId,
    required this.anchor,
    required this.copy,
    required this.entries,
    required this.animation,
    required this.onSelected,
    this.indent = 0,
    this.reduceMotion = false,
    this.onReact,
    this.onMoreEmoji,
    super.key,
  });

  /// The message, which the keys carry.
  final String messageId;

  /// Where the message's row was, in the menu's coordinates.
  final Rect anchor;

  /// How far the message's text starts in from the row's start edge, which
  /// the bar and the actions line up with.
  final double indent;

  /// What to draw for the message, usually its row with no callbacks.
  final Widget copy;

  /// The actions under the message. Empty leaves the list out.
  final List<QuarkMenuEntry> entries;

  /// The route's animation, which the lift follows.
  final Animation<double> animation;

  /// Whether to drop the lift and its shadow.
  final bool reduceMotion;

  /// Called with the chosen action, for the caller to run once the menu
  /// has closed.
  final ValueChanged<VoidCallback> onSelected;

  /// Reacts with an emoji from the bar. Null leaves the bar out.
  final ValueChanged<String>? onReact;

  /// Asks for an emoji beyond the bar's. Null leaves "More emoji" out.
  final VoidCallback? onMoreEmoji;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final media = MediaQuery.of(context);
    final onReact = this.onReact;
    final onMoreEmoji = this.onMoreEmoji;
    final card = Material(
      key: ValueKey('message_context_copy_$messageId'),
      color: tokens.card,
      elevation: reduceMotion ? 0 : 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(bottom: tokens.spacingSm),
          child: IgnorePointer(child: copy),
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          // Taps go through to the route's barrier, which closes the menu.
          child: IgnorePointer(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: ColoredBox(
                color: tokens.background.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        CustomMultiChildLayout(
          delegate: ChatContextMenuLayout(
            anchor: anchor,
            padding:
                media.padding +
                media.viewInsets +
                EdgeInsets.all(tokens.spacingSm),
            gap: tokens.spacingSm,
            indent: indent,
            textDirection: Directionality.of(context),
          ),
          children: [
            if (onReact != null)
              LayoutId(
                id: ChatContextMenuLayout.bar,
                child: ChatQuickReactionBar(
                  messageId: messageId,
                  onReact: (emoji) => onSelected(() => onReact(emoji)),
                  onMoreEmoji: onMoreEmoji == null
                      ? null
                      : () => onSelected(onMoreEmoji),
                ),
              ),
            LayoutId(
              id: ChatContextMenuLayout.message,
              child: reduceMotion
                  ? card
                  : ScaleTransition(
                      key: ValueKey('message_context_lift_$messageId'),
                      scale: animation.drive(
                        Tween<double>(
                          begin: 1,
                          end: 1.03,
                        ).chain(CurveTween(curve: Curves.easeOutCubic)),
                      ),
                      child: card,
                    ),
            ),
            if (entries.isNotEmpty)
              LayoutId(
                id: ChatContextMenuLayout.actions,
                child: ChatContextMenuActions(
                  entries: entries,
                  onSelected: onSelected,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
