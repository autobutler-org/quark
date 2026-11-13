import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/host_item.dart';
import '../../theme/quark_tokens.dart';

/// The top of `QuarkDrawer`: the product name as a wordmark in Newsreader, the
/// mark beside it, on the canvas, and the Quark on screen. With more than one
/// saved, the
/// header opens a menu for switching to another (#2230, #4098).
///
/// Key prefixes: `drawer_wordmark` on the product name, `drawer_host` on the
/// header when it names a Quark, `drawer_host_header` on the button that opens
/// the menu, and `drawer_host_<index>` on each Quark in it.
class QuarkDrawerHeader extends StatelessWidget {
  /// Creates the header for [hosts], naming the one at [activeHostIndex].
  const QuarkDrawerHeader({
    this.hosts = const [],
    this.activeHostIndex = -1,
    this.onSelectHost,
    super.key,
  });

  /// Every saved Quark, in the order the menu lists them.
  final List<HostItem> hosts;

  /// The index into [hosts] of the Quark on screen. Out of range shows the
  /// product name alone.
  final int activeHostIndex;

  /// Called with the index of the Quark picked from the menu, including the
  /// active one. Null leaves the header a label.
  final ValueChanged<int>? onSelectHost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final active = activeHostIndex >= 0 && activeHostIndex < hosts.length
        ? hosts[activeHostIndex]
        : null;
    final wordmarkStyle = theme.textTheme.headlineSmall?.copyWith(
      fontFamily: 'Newsreader',
      package: 'quark_widgets',
      fontWeight: FontWeight.w500,
      color: tokens.foreground,
    );
    final wordmarkSize = wordmarkStyle?.fontSize ?? 24;
    // Newsreader's cap height sits 0.1em above the em box (ascender 1470,
    // descender 530, cap height 1340, em 2000). The row centers the em box on
    // the mark, so the letters have to move down by that much to line up.
    final wordmark = Row(
      key: const ValueKey('drawer_wordmark'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'assets/mark.png',
          package: 'quark_widgets',
          width: wordmarkSize,
          height: wordmarkSize,
          excludeFromSemantics: true,
          filterQuality: FilterQuality.medium,
        ),
        SizedBox(width: tokens.spacingSm),
        Flexible(
          child: Transform.translate(
            offset: Offset(0, wordmarkSize * 0.1),
            child: Text(
              'Quark',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: wordmarkStyle,
            ),
          ),
        ),
      ],
    );

    // The drawer list is flush to the screen edge. Keep the status-bar inset
    // the old filled header carried, without its 160dp slab.
    Widget padded(Widget child) => SafeArea(
      bottom: false,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );

    if (active == null || active.name.isEmpty) {
      return padded(wordmark);
    }

    final onSelect = onSelectHost;
    final switchable = hosts.length > 1 && onSelect != null;
    final label = Column(
      key: const ValueKey('drawer_host'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        wordmark,
        SizedBox(height: tokens.spacingMd),
        Row(
          children: [
            // One line each, clipped with an ellipsis: a nickname is whatever
            // someone typed, and the drawer is 304dp wide on every phone.
            Expanded(
              child: Text(
                active.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: tokens.foreground,
                ),
              ),
            ),
            if (switchable)
              Icon(
                QuarkIcons.unfold_more,
                size: 20,
                color: tokens.mutedForeground,
              ),
          ],
        ),
        if (active.address.isNotEmpty)
          Text(
            active.address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.mutedForeground,
            ),
          ),
      ],
    );

    if (!switchable) return padded(label);

    return padded(
      InkWell(
        key: const ValueKey('drawer_host_header'),
        onTap: () => _showMenu(context, onSelect),
        child: label,
      ),
    );
  }

  /// Opens the switcher under the ⇅ icon, right-aligned to it.
  ///
  /// A [PopupMenuButton] anchors to the whole header, and a header spanning
  /// most of a phone's width reads as closer to the left edge, so Flutter
  /// grows the menu rightward from the header's left edge. Handing
  /// [showMenu] a `left` larger than its `right` is how its layout is told
  /// to align the menu's right edge instead: `right` is the icon's right
  /// edge, which sits inside the header's 16dp padding.
  Future<void> _showMenu(
    BuildContext context,
    ValueChanged<int> onSelect,
  ) async {
    final header = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final bottomRight = header.localToGlobal(
      header.size.bottomRight(const Offset(-16, 0)),
      ancestor: overlay,
    );
    final picked = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        overlay.size.width,
        bottomRight.dy,
        overlay.size.width - bottomRight.dx,
        overlay.size.height - bottomRight.dy,
      ),
      items: [
        for (final (index, host) in hosts.indexed)
          CheckedPopupMenuItem(
            key: ValueKey('drawer_host_$index'),
            value: index,
            checked: index == activeHostIndex,
            child: Text(
              host.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
    if (picked != null) onSelect(picked);
  }
}
