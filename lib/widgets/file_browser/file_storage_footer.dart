import 'package:quark/services/health_service.dart';
import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the whole-disk figure in the footer means.
///
/// The number is the Quark's disk, system and all, so a brand-new Quark with
/// no files in it still shows tens of gigabytes used. Beside "No files yet"
/// that reads as "Quark has already eaten my disk" rather than "this is the
/// whole device" (#2024), so the footer says which it is.
const String kStorageFooterScope = 'Device storage';

/// The longer form, for the tooltip.
const String kStorageFooterExplanation =
    'The whole disk inside your Quark, including its system software — not '
    'just the files you have put here.';

/// The capacity row at the bottom of the Files page. It renders whatever
/// [status] the page last fetched and never fetches on its own, so the page's
/// refresh (button, timer, server events) is what keeps it current (#2151).
class FileStorageFooter extends StatelessWidget {
  const FileStorageFooter({super.key, this.status});

  /// The latest health reading, or null before one has arrived (or when the
  /// Quark's health endpoint is unreachable), which shows the placeholder.
  final HealthStatus? status;

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    return '${value.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final diskPercent = status == null
        ? 0.0
        : (status.diskPercent / 100).clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;
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
          message: kStorageFooterExplanation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  QuarkIcons.storage_rounded,
                  size: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 8),
                // Flexible with an ellipsis: the label now carries the scope as
                // well as the figures, and the bar beside it still has to fit
                // on a phone.
                Flexible(
                  child: Text(
                    status == null
                        ? kStorageFooterScope
                        : '$kStorageFooterScope  ·  '
                              '${_formatBytes(status.diskUsedBytes)}'
                              ' / ${_formatBytes(status.diskTotalBytes)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: QuarkStorageBar(usedFraction: diskPercent),
                  ),
                ),
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
    );
  }
}
