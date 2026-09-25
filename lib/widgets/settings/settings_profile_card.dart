import 'package:flutter/material.dart';
import 'package:quark/widgets/users/user_avatar.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Profile card at the top of Settings → Account (#2419): the signed-in
/// user's picture, a button to choose a new one and, when there is one, a
/// button to remove it.
///
/// The Quark crops the picture square and resizes it, so what the circle
/// shows after an upload is what everyone else sees.
///
/// Keys: `settings_profile_pick`, `settings_profile_remove`, and the avatar's
/// `avatar_<userId>`.
class SettingsProfileCard extends StatelessWidget {
  /// Creates the card.
  const SettingsProfileCard({
    required this.userId,
    required this.username,
    required this.avatarVersion,
    required this.isBusy,
    required this.error,
    required this.onPick,
    required this.onRemove,
    super.key,
  });

  /// The signed-in account's id, or null until the Quark has said.
  final int? userId;

  /// The signed-in username, drawn as initials without a picture.
  final String username;

  /// The picture's version, or null when there is none.
  final int? avatarVersion;

  /// Whether an upload or removal is under way; the buttons wait for it.
  final bool isBusy;

  /// Why the last change failed, from `Errors.avatar`, or null.
  final String? error;

  /// Called when the user taps Choose picture.
  final VoidCallback onPick;

  /// Called when the user taps Remove.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final id = userId;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profile', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                if (id != null)
                  UserAvatar(
                    userId: id,
                    name: username,
                    version: avatarVersion,
                    size: 64,
                  )
                else
                  QuarkAvatar(id: username, name: username, size: 64),
                const SizedBox(width: 16),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('settings_profile_pick'),
                        onPressed: isBusy || id == null ? null : onPick,
                        icon: const Icon(QuarkIcons.image_outlined),
                        label: const Text('Choose picture'),
                      ),
                      if (avatarVersion != null)
                        TextButton(
                          key: const ValueKey('settings_profile_remove'),
                          onPressed: isBusy ? null : onRemove,
                          child: const Text('Remove'),
                        ),
                      if (isBusy) const QuarkLoader(size: 20),
                    ],
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
