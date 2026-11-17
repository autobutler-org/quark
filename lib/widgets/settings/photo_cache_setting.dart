import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/photo_disk_cache.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/photo_disk_cache_config.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Settings section for the photos this device keeps on disk (#4221):
/// how much it holds now, how much room previews may take, and a button that
/// empties it.
///
/// App-coupled: it reads the size from [PhotoDiskCache] and saves the budget
/// through [AppSettings]. Shown on iOS, Android and desktop only; the web
/// leaves caching to the browser.
///
/// Keys: `settings_photo_cache_budget` on the dropdown,
/// `settings_photo_cache_clear` on the button.
///
/// ```dart
/// if (!kIsWeb) const PhotoCacheSetting()
/// ```
class PhotoCacheSetting extends StatefulWidget {
  /// Creates the section. A test passes [sizeInBytes] and [clear] in place
  /// of [PhotoDiskCache]'s.
  const PhotoCacheSetting({
    this.sizeInBytes = PhotoDiskCache.sizeInBytes,
    this.clear = PhotoDiskCache.clear,
    super.key,
  });

  /// Reads how many bytes the cache holds.
  final Future<int> Function() sizeInBytes;

  /// Empties the cache.
  final Future<void> Function() clear;

  @override
  State<PhotoCacheSetting> createState() => PhotoCacheSettingState();
}

/// The state of [PhotoCacheSetting]: the size last read and whether a clear
/// is under way.
class PhotoCacheSettingState extends State<PhotoCacheSetting> {
  int? _usedBytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_readSize());
  }

  Future<void> _readSize() async {
    final used = await widget.sizeInBytes();
    if (mounted) setState(() => _usedBytes = used);
  }

  Future<void> _setBudget(int bytes) async {
    await AppSettings.instance.setPhotoPreviewCacheBytes(bytes);
    await _readSize();
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    await widget.clear();
    if (!mounted) return;
    setState(() => _clearing = false);
    await _readSize();
  }

  @override
  Widget build(BuildContext context) {
    final used = _usedBytes;
    return QuarkSection(
      title: 'Photos on this device',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Photos you open are kept on this device, so they open quickly '
            'and without a connection. They stay private to this app.'
            '${used == null ? '' : ' Now using ${StorageDevice.formatBytes(used)}.'}',
          ),
          const SizedBox(height: 12),
          QuarkDropdownField<int>(
            key: const ValueKey('settings_photo_cache_budget'),
            initialValue: AppSettings.instance.photoPreviewCacheBytes.value,
            items: [
              for (final bytes in PhotoDiskCacheConfig.previewBudgetChoices)
                DropdownMenuItem(
                  value: bytes,
                  child: Text('Up to ${StorageDevice.formatBytes(bytes)}'),
                ),
            ],
            onChanged: (bytes) {
              if (bytes != null) unawaited(_setBudget(bytes));
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: const ValueKey('settings_photo_cache_clear'),
              onPressed: _clearing || used == 0 ? null : _clear,
              icon: const Icon(QuarkIcons.delete_outline),
              label: const Text('Clear cached photos'),
            ),
          ),
        ],
      ),
    );
  }
}
