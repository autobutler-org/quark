import 'package:flutter/material.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// [WelcomeCard] wired to [AppSettings]: the greeting on the Files landing
/// (#2022).
///
/// What it shows follows [AppSettings.filesWelcome]. A new owner gets the
/// card with the start-here actions, which stays until dismissed. An explicit
/// sign-in gets one line, "Welcome back", and no actions. Anything else — a
/// stored session, a reload — renders nothing.
///
/// The greeting uses [AppSettings.username] and leaves the name out when
/// there is none. Vault is admin-only, so its action follows
/// [AppSettings.isAdmin], which arrives after the page is built.
///
/// The actions themselves belong to the page: uploading, creating a folder
/// and navigating are handed in.
///
/// Keys: `files_welcome` for the card, `welcome_upload`, `welcome_new_folder`
/// and `welcome_vault` for the actions, and the package's
/// `welcome_card_dismiss`.
class FilesWelcomeCard extends StatelessWidget {
  /// Creates the Files greeting backed by [AppSettings.instance].
  const FilesWelcomeCard({
    required this.onUpload,
    required this.onCreateFolder,
    required this.onOpenVault,
    super.key,
  });

  /// Starts an upload into the folder on screen.
  final VoidCallback onUpload;

  /// Starts creating a folder in the folder on screen.
  final VoidCallback onCreateFolder;

  /// Opens Vault. Only offered to an admin.
  final VoidCallback onOpenVault;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([settings.filesWelcome, settings.isAdmin]),
      builder: (context, _) {
        final welcome = settings.filesWelcome.value;
        if (welcome == FilesWelcome.none) return const SizedBox.shrink();

        final tokens = QuarkTokens.of(context);
        final username = settings.username;
        final name = username == null || username.isEmpty ? '' : ', $username';
        final isOwner = welcome == FilesWelcome.newOwner;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.spacingMd,
            tokens.spacingSm,
            tokens.spacingMd,
            tokens.spacingSm,
          ),
          child: WelcomeCard(
            key: const ValueKey('files_welcome'),
            headline: isOwner ? 'Welcome$name' : 'Welcome back$name',
            message: isOwner
                ? 'Your files stay on your Quark. Start by adding something.'
                : null,
            actions: [
              if (isOwner) ...[
                QuarkBarChip(
                  key: const ValueKey('welcome_upload'),
                  icon: QuarkIcons.upload_rounded,
                  label: 'Upload',
                  keepLabel: true,
                  onPressed: onUpload,
                ),
                QuarkBarChip(
                  key: const ValueKey('welcome_new_folder'),
                  icon: QuarkIcons.create_new_folder_outlined,
                  label: 'New folder',
                  keepLabel: true,
                  onPressed: onCreateFolder,
                ),
                if (settings.isAdmin.value)
                  QuarkBarChip(
                    key: const ValueKey('welcome_vault'),
                    icon: QuarkIcons.lock_outline,
                    label: 'Open Vault',
                    keepLabel: true,
                    onPressed: onOpenVault,
                  ),
              ],
            ],
            onDismiss: settings.dismissFilesWelcome,
          ),
        );
      },
    );
  }
}
