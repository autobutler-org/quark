import 'package:flutter/material.dart';
import 'package:quark/services/users_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A [QuarkAvatar] for the account [userId], showing its profile picture from
/// the Quark when [version] says it has one, and its initials otherwise.
///
/// [version] is the picture's `avatarUpdatedAt`, which goes into the URL (see
/// [UsersService.avatarUrl]) so a changed picture is fetched afresh. A picture
/// that fails to load falls back to the initials.
///
/// Key prefixes: `avatar_<userId>`, from [QuarkAvatar].
class UserAvatar extends StatelessWidget {
  /// Creates the avatar.
  const UserAvatar({
    required this.userId,
    required this.name,
    this.version,
    this.size = QuarkAvatar.defaultSize,
    super.key,
  });

  /// The account's id.
  final int userId;

  /// The account's name, drawn as initials without a picture.
  final String name;

  /// The picture's version, or null when the account has none.
  final int? version;

  /// The diameter of the circle.
  final double size;

  @override
  Widget build(BuildContext context) {
    final id = '$userId';
    final v = version;
    return QuarkAvatar(
      id: id,
      name: name,
      size: size,
      imageBuilder: v == null
          ? null
          : (context, size) => Image.network(
              UsersService.avatarUrl(userId, version: v).toString(),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  QuarkAvatar(id: id, name: name, size: size),
            ),
    );
  }
}
