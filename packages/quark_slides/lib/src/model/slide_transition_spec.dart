import '../format/json_fields.dart';
import 'slide_transition_direction.dart';
import 'slide_transition_kind.dart';

/// How a slide comes onto the screen when presenting: a [kind] of effect,
/// the [direction] a push or wipe moves in, and how long it lasts.
///
/// A slide's own transition plays as the show arrives at it; a slide with
/// none follows `Presentation.defaultTransition`. Stored in `.qslide` as
///
/// ```json
/// "transition": {"kind": "push", "direction": "up", "duration": 800}
/// ```
///
/// with the default [direction] and [durationMs] left out. It is named
/// `SlideTransitionSpec` rather than `SlideTransition` so it does not
/// collide with Flutter's `SlideTransition` widget in a file importing both.
///
/// ```dart
/// doc.setSlideTransition(slideId, const SlideTransitionSpec.fade());
/// doc.applyTransitionToAll(
///   const SlideTransitionSpec(
///     kind: SlideTransitionKind.push,
///     direction: SlideTransitionDirection.up,
///   ),
/// );
/// ```
class SlideTransitionSpec {
  /// Creates a transition; [durationMs] is kept within [minDurationMs] and
  /// [maxDurationMs].
  const SlideTransitionSpec({
    this.kind = SlideTransitionKind.none,
    this.direction = SlideTransitionDirection.left,
    int durationMs = defaultDurationMs,
    this.extra = const {},
  }) : durationMs = durationMs < minDurationMs
            ? minDurationMs
            : durationMs > maxDurationMs
                ? maxDurationMs
                : durationMs;

  /// A fade lasting [durationMs].
  const SlideTransitionSpec.fade({int durationMs = defaultDurationMs})
      : this(kind: SlideTransitionKind.fade, durationMs: durationMs);

  /// No transition: an instant cut. The deck's default when it sets none.
  static const none = SlideTransitionSpec();

  /// The shortest transition, in milliseconds.
  static const minDurationMs = 200;

  /// The longest transition, in milliseconds.
  static const maxDurationMs = 2000;

  /// The length of a transition that sets none, in milliseconds.
  static const defaultDurationMs = 500;

  /// The effect.
  final SlideTransitionKind kind;

  /// The way a push or wipe moves; ignored by the other kinds.
  final SlideTransitionDirection direction;

  /// How long the effect lasts, in milliseconds, from [minDurationMs] to
  /// [maxDurationMs].
  final int durationMs;

  /// Fields a newer writer added that this version does not read, and the
  /// `kind` it wrote when this version does not know it.
  final JsonMap extra;

  /// How long the effect lasts.
  Duration get duration => Duration(milliseconds: durationMs);

  /// The transition played under reduced motion: none stays a cut, and
  /// every other kind becomes the shortest fade, which carries the change
  /// without movement.
  SlideTransitionSpec get reducedMotion => kind == SlideTransitionKind.none
      ? this
      : SlideTransitionSpec(
          kind: SlideTransitionKind.fade,
          durationMs: minDurationMs,
        );

  /// The transition played stepping back onto a slide: the same, moving in
  /// the [SlideTransitionDirection.reversed] direction.
  SlideTransitionSpec get reversed => copyWith(direction: direction.reversed);

  static const _known = {'kind', 'direction', 'duration'};

  /// Reads a transition from its `.qslide` object at [path].
  factory SlideTransitionSpec.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final kind = enumByName(
      json,
      'kind',
      SlideTransitionKind.values,
      SlideTransitionKind.none,
    );
    final duration = optionalNumber(json, 'duration', path);
    return SlideTransitionSpec(
      kind: kind,
      direction: enumByName(
        json,
        'direction',
        SlideTransitionDirection.values,
        SlideTransitionDirection.left,
      ),
      durationMs: duration?.round() ?? defaultDurationMs,
      // A kind this version does not know rides along in extra, so saving
      // writes it back rather than "none".
      extra: unknownFields(
        json,
        json['kind'] == kind.name ? _known : (_known.toSet()..remove('kind')),
      ),
    );
  }

  /// The transition as its `.qslide` object.
  JsonMap toJson() => {
        'kind': kind.name,
        if (direction != SlideTransitionDirection.left)
          'direction': direction.name,
        if (durationMs != defaultDurationMs) 'duration': durationMs,
        ...extra,
      };

  /// Returns a copy with the given fields replaced. Setting [kind] drops a
  /// kind this version did not know.
  SlideTransitionSpec copyWith({
    SlideTransitionKind? kind,
    SlideTransitionDirection? direction,
    int? durationMs,
  }) =>
      SlideTransitionSpec(
        kind: kind ?? this.kind,
        direction: direction ?? this.direction,
        durationMs: durationMs ?? this.durationMs,
        extra:
            kind == null ? extra : Map.unmodifiable({...extra}..remove('kind')),
      );

  @override
  bool operator ==(Object other) =>
      other is SlideTransitionSpec &&
      other.kind == kind &&
      other.direction == direction &&
      other.durationMs == durationMs &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(kind, direction, durationMs, jsonHash(extra));

  @override
  String toString() =>
      'SlideTransitionSpec(${kind.name}, ${direction.name}, ${durationMs}ms)';
}
