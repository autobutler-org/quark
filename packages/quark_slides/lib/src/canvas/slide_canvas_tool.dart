/// What a pointer does on an editing `SlideCanvas`.
enum SlideCanvasTool {
  /// Select, move, resize and rotate elements.
  select,

  /// Draw a text box: click to place one at the default width, or drag to
  /// size it. The new box opens for typing and the canvas hands the tool
  /// back to [select] through `onToolChanged`.
  text,
}
