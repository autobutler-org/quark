import 'package:material_ui/material_ui.dart';
import 'package:quark/models/photo_map_tiles.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The photo map's settings (#3557), on the General tab of Settings: whether
/// Photos shows its Locations view and the viewer's map preview at all, and
/// where the map's tiles come from. Off, neither shows and no tile is ever
/// fetched. OpenStreetMap's public servers are offered only as an opt-in,
/// with what they learn said beside them.
///
/// Reads and writes [AppSettings] itself, so it is an app widget. Keys:
/// `settings_photo_map`, `settings_photo_map_tiles_<source>`,
/// `settings_photo_map_custom_url`.
class PhotoMapSettings extends StatefulWidget {
  /// Creates the section.
  const PhotoMapSettings({super.key});

  @override
  State<PhotoMapSettings> createState() => _PhotoMapSettingsState();
}

class _PhotoMapSettingsState extends State<PhotoMapSettings> {
  final _settings = AppSettings.instance;
  late final _customUrl = TextEditingController(
    text: _settings.photoMapCustomTileUrl.value,
  );

  @override
  void dispose() {
    _customUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        _settings.photoMapEnabled,
        _settings.photoMapTiles,
      ]),
      builder: (context, _) {
        final enabled = _settings.photoMapEnabled.value;
        final tiles = _settings.photoMapTiles.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsRow.toggle(
              key: const ValueKey('settings_photo_map'),
              title: const Text('Show photos on a map'),
              subtitle: const Text(
                'Adds Locations to Photos, placed by the GPS position each '
                'photo saved when it was taken. Off, no map is shown or '
                'downloaded.',
              ),
              value: enabled,
              onChanged: _settings.setPhotoMapEnabled,
            ),
            if (enabled)
              RadioGroup<PhotoMapTiles>(
                groupValue: tiles,
                onChanged: (v) {
                  if (v != null) _settings.setPhotoMapTiles(v);
                },
                child: Column(
                  children: [
                    for (final source in PhotoMapTiles.values)
                      RadioListTile<PhotoMapTiles>(
                        key: ValueKey(
                          'settings_photo_map_tiles_${source.storageValue}',
                        ),
                        value: source,
                        title: Text(switch (source) {
                          PhotoMapTiles.quark => 'Map from this Quark',
                          PhotoMapTiles.openStreetMap =>
                            'Map from OpenStreetMap',
                          PhotoMapTiles.custom => 'Map from my own tile server',
                        }),
                        subtitle: Text(switch (source) {
                          PhotoMapTiles.quark =>
                            'Nothing leaves your home. Needs a map pack '
                                'installed on the Quark.',
                          PhotoMapTiles.openStreetMap =>
                            'Tells OpenStreetMap which area you are looking '
                                'at, never where a photo was taken.',
                          PhotoMapTiles.custom =>
                            'Tells that server which area you are looking at.',
                        }),
                      ),
                  ],
                ),
              ),
            if (enabled && tiles == PhotoMapTiles.custom)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: tokens.spacingMd),
                child: QuarkWidget.textField(
                  key: const ValueKey('settings_photo_map_custom_url'),
                  controller: _customUrl,
                  hintText: 'https://tiles.example/{z}/{x}/{y}.png',
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (url) => _settings.setPhotoMapTiles(
                    PhotoMapTiles.custom,
                    customUrl: url,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
