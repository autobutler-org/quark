import 'package:flutter/material.dart';

/// A trim range bar with two draggable handles (start and end).
///
/// Renders a track with:
/// - A semi-transparent overlay for the un-selected regions (before start, after end)
/// - A highlighted selected region between start and end
/// - Draggable circular handles at start and end positions
/// - Timestamp labels above each handle
class TrimBar extends StatelessWidget {
  final double start; // 0.0–1.0 fraction
  final double end; // 0.0–1.0 fraction
  final Duration duration;
  final ValueChanged<double> onStartChanged;
  final ValueChanged<double> onEndChanged;

  const TrimBar({
    super.key,
    required this.start,
    required this.end,
    required this.duration,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  static const _handleSize = 24.0;
  static const _trackHeight = 6.0;

  // The label sits in a fixed slot above the handle. Reserving the slot (rather
  // than letting the label size itself around the handle) is what keeps the
  // handle's center free to land exactly on the track.
  static const _labelHeight = 14.0;
  static const _labelWidth = 72.0;
  static const _labelGap = 2.0;
  static const _barHeight = _labelHeight + _labelGap + _handleSize;

  /// Shared center line for the handles and the track, measured from the top
  /// of the bar. Everything vertical is anchored to this so the handles and
  /// the track share a center instead of each being centered independently.
  static const _centerY = _labelHeight + _labelGap + _handleSize / 2;

  String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final tenths = (ms % 1000) ~/ 100;
    if (h > 0) {
      return '${h}h${m.toString().padLeft(2, '0')}m${s.toString().padLeft(2, '0')}s';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.$tenths';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final totalMs = duration.inMilliseconds;
    final startLabel = _formatMs((start * totalMs).round());
    final endLabel = _formatMs((end * totalMs).round());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final startX = start * width;
          final endX = end * width;

          return SizedBox(
            height: _barHeight,
            child: Stack(
              children: [
                // Track background
                Positioned(
                  left: 0,
                  right: 0,
                  top: _centerY - _trackHeight / 2,
                  child: Container(
                    height: _trackHeight,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(_trackHeight / 2),
                    ),
                  ),
                ),
                // Selected region highlight
                Positioned(
                  left: startX,
                  width: (endX - startX).clamp(0.0, width),
                  top: _centerY - _trackHeight / 2,
                  child: Container(
                    height: _trackHeight,
                    color: primary.withValues(alpha: 0.7),
                  ),
                ),
                // Start handle + label
                ..._buildHandle(
                  centerX: startX,
                  width: width,
                  label: startLabel,
                  color: primary,
                  onDragDelta: (dx) => onStartChanged(
                    ((startX + dx) / width).clamp(0.0, end - 0.01),
                  ),
                ),
                // End handle + label
                ..._buildHandle(
                  centerX: endX,
                  width: width,
                  label: endLabel,
                  color: primary,
                  onDragDelta: (dx) => onEndChanged(
                    ((endX + dx) / width).clamp(start + 0.01, 1.0),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The label and the handle are positioned separately on purpose. Nesting
  /// them in a single Column made the Column — not the handle — the thing
  /// being positioned, so the handle inherited the label's width and height
  /// and drifted right and down off the track.
  List<Widget> _buildHandle({
    required double centerX,
    required double width,
    required String label,
    required Color color,
    required ValueChanged<double> onDragDelta,
  }) {
    // Slot widths can exceed the bar on very narrow layouts; keep the clamp
    // bounds ordered so they stay valid.
    final labelLeftMax = (width - _labelWidth).clamp(0.0, double.infinity);
    final handleLeftMax = (width - _handleSize).clamp(0.0, double.infinity);

    return [
      Positioned(
        top: 0,
        left: (centerX - _labelWidth / 2).clamp(0.0, labelLeftMax),
        width: _labelWidth,
        height: _labelHeight,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ),
      Positioned(
        top: _centerY - _handleSize / 2,
        left: (centerX - _handleSize / 2).clamp(0.0, handleLeftMax),
        child: GestureDetector(
          onHorizontalDragUpdate: (details) => onDragDelta(details.delta.dx),
          child: Container(
            width: _handleSize,
            height: _handleSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}
