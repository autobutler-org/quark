import 'package:material_ui/material_ui.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_upload_chip.dart';
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
/// there is none. Every account has its own vault (#3461), so Open Vault is
/// offered to everyone.
///
/// The actions themselves belong to the page: uploading, creating a folder
/// and navigating are handed in. With [canChooseDevice], Upload and New
/// folder each get a second action that asks which device to write to
/// (#3194).
///
/// Keys: `files_welcome` for the card, `welcome_upload`, `welcome_new_folder`
/// and `welcome_vault` for the actions, `welcome_upload_choose` and
/// `welcome_new_folder_choose` for their choose-device segments, and the
/// package's `welcome_card_dismiss`.
class FilesWelcomeCard extends StatelessWidget {
  /// Creates the Files greeting backed by [AppSettings.instance].
  const FilesWelcomeCard({
    required this.onUpload,
    required this.onCreateFolder,
    required this.onOpenVault,
    this.canChooseDevice = false,
    super.key,
  });

  /// Starts an upload into the folder on screen.
  final DeviceWriteCallback onUpload;

  /// Starts creating a folder in the folder on screen.
  final DeviceWriteCallback onCreateFolder;

  /// Opens Vault.
  final VoidCallback onOpenVault;

  /// Whether there is more than one device to write to.
  final bool canChooseDevice;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return ListenableBuilder(
      listenable: settings.filesWelcome,
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
                QuarkBarSplitChip(
                  key: const ValueKey('welcome_upload'),
                  icon: QuarkIcons.upload_rounded,
                  label: 'Upload',
                  keepLabel: true,
                  onPressed: onUpload,
                  onSecondaryPressed: canChooseDevice
                      ? () => onUpload(chooseDevice: true)
                      : null,
                ),
                QuarkBarSplitChip(
                  key: const ValueKey('welcome_new_folder'),
                  icon: QuarkIcons.create_new_folder_outlined,
                  label: 'New folder',
                  keepLabel: true,
                  onPressed: onCreateFolder,
                  onSecondaryPressed: canChooseDevice
                      ? () => onCreateFolder(chooseDevice: true)
                      : null,
                ),
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
