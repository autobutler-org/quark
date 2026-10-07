/// How one slide gives way to the next when presenting.
///
/// An unknown kind in a `.qslide` file reads as [none] and is written back
/// as it was read, so a newer writer's effect survives an older editor.
enum SlideTransitionKind {
  /// An instant cut: the new slide simply replaces the old.
  none,

  /// The new slide fades in over the old.
  fade,

  /// The new slide pushes the old off the screen in the transition's
  /// direction.
  push,

  /// The new slide is uncovered over the old by an edge sweeping in the
  /// transition's direction.
  wipe,

  /// The new slide grows from the center as it fades in.
  zoom;

  /// Whether the kind moves in a `SlideTransitionDirection`.
  bool get isDirectional => this == push || this == wipe;
}
