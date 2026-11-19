import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/kept_albums_controller.dart';
import 'package:quark/models/kept_album.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Settings section listing the albums kept on this phone for offline
/// viewing (#4222): each one's name, what it keeps, the space it takes and
/// where its download stands, with a button that stops keeping it and frees
/// that space.
///
/// App-coupled: it listens to [KeptAlbumsController]. Shown on iOS, Android
/// and desktop only, beside the photo cache section.
///
/// Keys: `settings_kept_album_<id>` on each row,
/// `settings_kept_album_remove_<id>` on its button.
///
/// ```dart
/// if (!kIsWeb) const KeptAlbumsSetting()
/// ```
class KeptAlbumsSetting extends StatelessWidget {
  /// Creates the section. A test passes its own [controller].
  const KeptAlbumsSetting({this.controller, super.key});

  /// The kept albums; [KeptAlbumsController.instance] when null.
  final KeptAlbumsController? controller;

  @override
  Widget build(BuildContext context) {
    final kept = controller ?? KeptAlbumsController.instance;
    return QuarkSection(
      title: 'Albums kept on this phone',
      child: ListenableBuilder(
        listenable: kept,
        builder: (context, _) {
          final albums = kept.albums;
          if (albums.isEmpty) {
            return const Text(
              'No albums are kept on this phone. To look at an album with no '
              'connection, open its menu in Photos and choose Keep on this '
              'phone.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final album in albums)
                ListTile(
                  key: ValueKey('settings_kept_album_${album.albumId}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(album.name),
                  subtitle: Text(
                    _describe(album, kept.progressOf(album.albumId)),
                  ),
                  trailing: TextButton(
                    key: ValueKey(
                      'settings_kept_album_remove_${album.albumId}',
                    ),
                    onPressed: () => unawaited(kept.stopKeeping(album.albumId)),
                    child: const Text('Remove'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _describe(KeptAlbum album, KeptAlbumProgress? progress) {
    final what = album.originals ? 'Full originals' : 'Previews';
    final size = StorageDevice.formatBytes(album.keptBytes);
    final status = switch (progress?.status) {
      KeptAlbumStatus.downloading =>
        'Downloading ${progress!.done} of ${progress.total}',
      KeptAlbumStatus.waitingForWifi => 'Waiting for Wi-Fi',
      KeptAlbumStatus.failed => 'Will try again',
      KeptAlbumStatus.ready => 'Ready offline',
      KeptAlbumStatus.pending || null => 'Waiting to sync',
    };
    return '$what · $size · $status';
  }
}
