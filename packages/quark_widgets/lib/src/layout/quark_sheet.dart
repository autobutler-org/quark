import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// Shows [builder]'s content in a [QuarkSheet] titled [title], as a modal
/// bottom sheet, and completes with whatever the sheet is popped with.
///
/// Every bottom sheet in the app goes through here, so each one gets the same
/// drag handle, header and close button, and the same height cap (#2585).
/// The sheet stops at [QuarkSheet.maxHeightFactor] of the height below the
/// status bar however tall its content is, so there is always scrim above it
/// to tap. It closes on a scrim tap, a swipe down on its handle or header,
/// system back, and its close button. Colors and corners come from
/// [QuarkTokens].
///
/// ```dart
/// final album = await showQuarkSheet<AlbumItem>(
///   context,
///   title: 'Add to album',
///   builder: (sheetContext) => AlbumPickerSheet(
///     albums: albums,
///     onPicked: (album) => Navigator.of(sheetContext).pop(album),
///   ),
/// );
/// ```
Future<T?> showQuarkSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  bool scrollable = true,
}) {
  final tokens = QuarkTokens.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: tokens.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(tokens.radiusLg),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (sheetContext) => QuarkSheet(
      title: title,
      onClose: () => Navigator.of(sheetContext).pop(),
      scrollable: scrollable,
      child: builder(sheetContext),
    ),
  );
}

/// The frame of a bottom sheet: a drag handle, a header with [title] and a
/// close button, and [child] scrolling beneath them.
///
/// The sheet is never taller than [maxHeightFactor] of the height it is
/// given, so a sheet shown over a page always leaves some of the page's scrim
/// showing. Only [child] scrolls, in a scroll view of the sheet's own, or by
/// itself when [scrollable] is false. The handle and header stay put, which
/// leaves them free to take a swipe down that dismisses a modal sheet rather
/// than scrolling it. The content moves clear of the keyboard and of the
/// bottom system inset.
///
/// Most callers want [showQuarkSheet], which puts this in a modal bottom
/// sheet. Use it directly for a sheet that is not a route, such as one drawn
/// over part of a page; closing it is the caller's, through [onClose].
///
/// Key prefixes: `quark_sheet_close` on the close button and
/// `quark_sheet_handle` on the drag handle.
///
/// ```dart
/// QuarkSheet(
///   title: 'Members',
///   onClose: controller.closeMembers,
///   scrollable: false,
///   child: QuarkMemberList(members: members),
/// );
/// ```
class QuarkSheet extends StatelessWidget {
  /// Creates a sheet titled [title] around [child].
  const QuarkSheet({
    required this.title,
    required this.child,
    required this.onClose,
    this.scrollable = true,
    super.key,
  });

  /// The most of its available height a sheet takes, leaving the rest as
  /// scrim to tap.
  static const double maxHeightFactor = 0.85;

  /// What the sheet is for, shown in its header.
  final String title;

  /// The sheet's content, given the space left under the header.
  final Widget child;

  /// Whether the sheet scrolls [child] and pads it. False hands [child] the
  /// space as it is, for content that scrolls itself, such as a `ListView`:
  /// one that fills its parent takes the whole height, and a shrink-wrapped
  /// one only what it needs.
  final bool scrollable;

  /// Fires when the close button is tapped. A modal sheet pops its route
  /// here; [showQuarkSheet] does that.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: available * maxHeightFactor),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: tokens.spacingSm),
                    child: Center(
                      child: Container(
                        key: const ValueKey('quark_sheet_handle'),
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: tokens.mutedForeground,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      tokens.spacingMd,
                      tokens.spacingXs,
                      tokens.spacingXs,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('quark_sheet_close'),
                          tooltip: 'Close',
                          icon: const Icon(QuarkIcons.close),
                          color: tokens.secondaryForeground,
                          onPressed: onClose,
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: scrollable
                        ? SingleChildScrollView(
                            padding: EdgeInsetsDirectional.fromSTEB(
                              tokens.spacingMd,
                              0,
                              tokens.spacingMd,
                              tokens.spacingMd,
                            ),
                            child: child,
                          )
                        : child,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
