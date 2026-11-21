import 'package:material_ui/material_ui.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/kept_albums_config.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the person chose in [KeepAlbumDialog].
typedef KeepAlbumChoice = ({bool originals, bool allowMobileData});

/// Asks how to keep an album on this phone for offline viewing (#4222):
/// previews only, the default, or full originals too, each with the space it
/// is guessed to take, and whether it may download over mobile data. Pops
/// with the choice, or null when canceled.
///
/// The choice is the form's own state, thrown away when the dialog closes.
///
/// Keys: `keep_album_previews` and `keep_album_originals` on the two
/// choices, `keep_album_mobile_data` on the switch, `keep_album_estimate` on
/// the size line, and `keep_album_confirm` and `keep_album_cancel` on the
/// buttons.
///
/// ```dart
/// final choice = await KeepAlbumDialog.show(
///   context,
///   albumName: album.name,
///   photoCount: album.itemCount,
/// );
/// ```
class KeepAlbumDialog extends StatefulWidget {
  /// Creates the dialog for the album named [albumName], holding
  /// [photoCount] photos.
  const KeepAlbumDialog({
    required this.albumName,
    required this.photoCount,
    super.key,
  });

  /// Shows the dialog and answers with the choice, or null when canceled.
  static Future<KeepAlbumChoice?> show(
    BuildContext context, {
    required String albumName,
    required int photoCount,
  }) => showDialog<KeepAlbumChoice>(
    context: context,
    builder: (_) =>
        KeepAlbumDialog(albumName: albumName, photoCount: photoCount),
  );

  /// The album being kept, named in the title.
  final String albumName;

  /// How many photos the album holds, which the size is guessed from.
  final int photoCount;

  @override
  State<KeepAlbumDialog> createState() => KeepAlbumDialogState();
}

/// The state of [KeepAlbumDialog]: the choice being made.
class KeepAlbumDialogState extends State<KeepAlbumDialog> {
  bool _originals = false;
  bool _allowMobileData = false;

  String _size({required bool originals}) => StorageDevice.formatBytes(
    KeptAlbumsConfig.estimateBytes(widget.photoCount, originals: originals),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final photos = widget.photoCount == 1
        ? '1 photo'
        : '${widget.photoCount} photos';
    return AlertDialog(
      title: Text('Keep "${widget.albumName}" on this phone'),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Its photos download in the background and stay in this app, '
              'so the album opens with no connection, even on a plane.',
            ),
            SizedBox(height: tokens.spacingMd),
            QuarkSegmentedChoice<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Previews', key: ValueKey('keep_album_previews')),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(
                    'Full originals',
                    key: ValueKey('keep_album_originals'),
                  ),
                ),
              ],
              selected: _originals,
              onChanged: (originals) => setState(() => _originals = originals),
            ),
            SizedBox(height: tokens.spacingSm),
            Text(
              'About ${_size(originals: _originals)} for $photos.',
              key: const ValueKey('keep_album_estimate'),
            ),
            SizedBox(height: tokens.spacingSm),
            SwitchListTile(
              key: const ValueKey('keep_album_mobile_data'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Also download over mobile data'),
              subtitle: const Text('Otherwise it waits for Wi-Fi.'),
              value: _allowMobileData,
              onChanged: (allow) => setState(() => _allowMobileData = allow),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('keep_album_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('keep_album_confirm'),
          onPressed: () => Navigator.of(
            context,
          ).pop((originals: _originals, allowMobileData: _allowMobileData)),
          child: const Text('Keep'),
        ),
      ],
    );
  }
}
