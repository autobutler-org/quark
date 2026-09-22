/// Tuning constants for dragging in the file browser: how long a folder stays highlighted after the pointer
/// leaves, and how fast the list scrolls near its edges.
class FileBrowserDragConfig {
  const FileBrowserDragConfig._();

  // How long to wait before clearing folder-hover state when moving between rows.
  static const int folderHoverExitDebounceMs = 90;

  // Vertical edge threshold (in logical px) that activates drag autoscroll.
  static const double autoScrollEdgeActivationPx = 92.0;

  // Base autoscroll delta per drag update near the edge.
  static const double autoScrollBaseDeltaPx = 3.0;

  // Additional autoscroll delta added as the cursor gets closer to the edge.
  static const double autoScrollMaxExtraDeltaPx = 17.0;
}
