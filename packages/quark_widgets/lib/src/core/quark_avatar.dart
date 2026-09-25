import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// A person's picture in a circle, or their initials on a color of their own
/// when there is no picture.
///
/// The package never fetches, so the picture comes in through [imageBuilder].
/// The app hands it a network image sized to the circle; the gallery hands it
/// a placeholder. Without a builder the avatar draws the initials of [name]
/// on a color derived from [QuarkTokens.primary], its hue turned by a hash
/// of [id], so the same person gets the same color everywhere and the color
/// still follows the theme. A builder whose image fails to load should return
/// a `QuarkAvatar` without one from its error builder, which lands back on the
/// initials.
///
/// Key prefixes: `avatar_<id>` on the circle.
///
/// ```dart
/// QuarkAvatar(
///   id: user.id,
///   name: user.name,
///   imageBuilder: user.hasAvatar
///       ? (context, size) => CachedNetworkImage(imageUrl: avatarUrl(user.id))
///       : null,
/// );
/// ```
class QuarkAvatar extends StatelessWidget {
  /// Creates an avatar for the person [id] called [name].
  const QuarkAvatar({
    required this.id,
    required this.name,
    this.size = defaultSize,
    this.imageBuilder,
    super.key,
  });

  /// The diameter an avatar takes when no [size] is given.
  static const double defaultSize = 32;

  /// The person's id, which picks the fallback color and names the key.
  final String id;

  /// The person's name, whose initials are the fallback. Also the avatar's
  /// semantics label.
  final String name;

  /// The diameter of the circle.
  final double size;

  /// Builds the picture, handed the circle's diameter. Clipped to the circle.
  /// Null draws the initials.
  final Widget Function(BuildContext context, double size)? imageBuilder;

  /// The one or two letters drawn for [name]: the first letter of its first
  /// and last words, or `?` for a blank name.
  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'[\s._-]+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return '?';
    final first = words.first.characters.first;
    if (words.length == 1) return first.toUpperCase();
    return (first + words.last.characters.first).toUpperCase();
  }

  /// The fallback color for [id]: [QuarkTokens.primary] with its hue turned
  /// by a stable hash of the id.
  static Color colorFor(String id, QuarkTokens tokens) {
    // String.hashCode is not stable across runs on every platform, so hash
    // the code units by hand.
    final hash = id.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff);
    final base = HSLColor.fromColor(tokens.primary);
    return base.withHue((base.hue + hash % 360) % 360).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final imageBuilder = this.imageBuilder;

    return Semantics(
      label: name,
      image: true,
      child: SizedBox.square(
        key: ValueKey('avatar_$id'),
        dimension: size,
        child: imageBuilder != null
            ? ClipOval(child: imageBuilder(context, size))
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: colorFor(id, tokens),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: ExcludeSemantics(
                    child: Text(
                      initialsOf(name),
                      style: TextStyle(
                        color: tokens.primaryForeground,
                        fontSize: size * 0.4,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
