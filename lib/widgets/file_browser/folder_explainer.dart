import 'package:flutter/material.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A short note atop the folders that hold structure rather than content
/// (#2476): `users`, `groups` and `groups/everyone` on the internal drive.
///
/// A member reaches these through My files and Groups without anything
/// saying why they exist, so each states its part of the model in one
/// paragraph: `users/<name>` is a home and private, a group's folder is open
/// to its members, `everyone` is every account's, and Share is how one
/// person gets one thing. Anywhere else, a USB drive's `users` folder
/// included, it renders nothing.
///
/// The note is a [WelcomeCard] with no actions and no dismiss button: it is
/// the folder's description, so it stays as long as the folder is open.
///
/// Keys: `folder_explainer` on the card.
class FolderExplainer extends StatelessWidget {
  /// Creates the note for [path] on the drive [serial], empty for internal.
  const FolderExplainer({required this.serial, required this.path, super.key});

  /// The drive the folder is on; empty for the internal drive.
  final String serial;

  /// The folder on screen.
  final String path;

  @override
  Widget build(BuildContext context) {
    final (headline, message) = isUsersDir(serial, path)
        ? (
            'Home folders',
            'Every account keeps its own files in users/<name>. A home is '
                'private to its owner unless they share something from it. '
                'Yours is under My files.',
          )
        : isGroupsDir(serial, path)
        ? (
            'Group folders',
            'Each group you are in has a folder here that all its members can '
                'open and add to; everyone is shared by every account. To give '
                'one person one file or folder, use Share instead.',
          )
        : isGroupRoot(serial, path) &&
              path.split('/').lastWhere((s) => s.isNotEmpty) == 'everyone'
        ? (
            'Shared with everyone',
            'Every account on this Quark can open and add to this folder, so '
                'anything you put here is visible to all of them.',
          )
        : (null, null);
    if (headline == null) return const SizedBox.shrink();

    final tokens = QuarkTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacingMd,
        tokens.spacingSm,
        tokens.spacingMd,
        tokens.spacingSm,
      ),
      child: WelcomeCard(
        key: const ValueKey('folder_explainer'),
        headline: headline,
        message: message,
      ),
    );
  }
}
