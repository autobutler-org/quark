import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/file_browser/file_storage_footer_scope.dart';
import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The capacity row at the bottom of the Files page. It renders whatever
/// [scope] the page last worked out and never fetches on its own, so the
/// page's refresh (button, timer, server events) is what keeps it current
/// (#2151). The scope is the drives the view is showing (#2895).
class FileStorageFooter extends StatelessWidget {
  const FileStorageFooter({
    super.key,
    this.scope = const FileStorageFooterScope(
      label: kStorageFooterScope,
      explanation: kStorageFooterExplanation,
    ),
  });

  /// What to measure and what to call it. Without figures — before a reading
  /// has arrived, or when none could be fetched — the footer shows only the
  /// label.
  final FileStorageFooterScope scope;

  @override
  Widget build(BuildContext context) {
    final usedBytes = scope.usedBytes;
    final totalBytes = scope.totalBytes;
    final diskPercent = scope.usedFraction;
    final colorScheme = Theme.of(context).colorScheme;
    final muted = QuarkTokens.of(context).mutedForeground;
    final barColor = QuarkStorageBar.colorForFraction(
      diskPercent,
      QuarkTokens.of(context),
    );
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.secondary,
        border: Border(top: BorderSide(color: colorScheme.outline)),
      ),
      // This footer is the last child of the page's Column, so it lands flush
      // against the physical bottom edge — where iOS draws the home indicator
      // and Android its gesture bar. `top: false` because the bar only ever
      // sits at the bottom; the decoration stays on the outer container so the
      // inset region is painted rather than left bare (#1598).
      child: SafeArea(
        top: false,
        child: Tooltip(
          message: scope.explanation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  Icon(QuarkIcons.storage_rounded, size: 14, color: muted),
                  const SizedBox(width: 8),
                  // Sized to its text, capped at half the row so a phone
                  // still cuts it short with an ellipsis (#1599). Not
                  // Flexible: beside the Expanded bar that split the free
                  // width in half, and the label left the unused part of its
                  // half empty after the percentage (#2447). The bar is the
                  // only flex child.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth / 2,
                    ),
                    child: Text(
                      usedBytes == null || totalBytes == null
                          ? scope.label
                          : '${scope.label}  ·  ${StorageDevice.formatBytes(usedBytes)}'
                                ' / ${StorageDevice.formatBytes(totalBytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: QuarkStorageBar(usedFraction: diskPercent)),
                  const SizedBox(width: 8),
                  if (diskPercent > 0)
                    Text(
                      '${(diskPercent * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: barColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
