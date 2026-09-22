import 'package:flutter/material.dart';
import '../../models/host_item.dart';

/// The top of `QuarkDrawer`: the product name, or the Quark on screen and,
/// with more than one saved, a menu for switching to another (#2230).
///
/// Key prefixes: `drawer_host` on the header when it names a Quark,
/// `drawer_host_header` on the button that opens the menu, and
/// `drawer_host_<index>` on each Quark in it.
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
    final onPrimary = theme.colorScheme.onPrimary;
    final muted = onPrimary.withValues(alpha: 0.8);
    final active = activeHostIndex >= 0 && activeHostIndex < hosts.length
        ? hosts[activeHostIndex]
        : null;

    if (active == null || active.name.isEmpty) {
      return Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Quark',
            style: theme.textTheme.titleLarge?.copyWith(color: onPrimary),
          ),
        ),
      );
    }

    final onSelect = onSelectHost;
    final switchable = hosts.length > 1 && onSelect != null;
    final label = Padding(
      key: const ValueKey('drawer_host'),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quark',
            style: theme.textTheme.labelMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              // One line each, clipped with an ellipsis: a nickname is whatever
              // someone typed, and the drawer is 304dp wide on every phone.
              Expanded(
                child: Text(
                  active.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(color: onPrimary),
                ),
              ),
              if (switchable)
                Icon(Icons.unfold_more_rounded, size: 20, color: muted),
            ],
          ),
          if (active.address.isNotEmpty)
            Text(
              active.address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
        ],
      ),
    );

    if (!switchable) return label;

    return SizedBox.expand(
      child: InkWell(
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
