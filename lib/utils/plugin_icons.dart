import 'package:flutter/widgets.dart';
import 'package:quark_icons/quark_icons.dart';

/// The icon a plugin manifest names, for its drawer row, its marketplace card
/// and any `icon` node on its page. A name this does not know is
/// [QuarkIcons.extension].
IconData pluginIcon(String name) => _icons[name] ?? QuarkIcons.extension;

const _icons = <String, IconData>{
  'waving_hand': QuarkIcons.waving_hand,
  'extension': QuarkIcons.extension,
  'download': QuarkIcons.download_outlined,
  'settings': QuarkIcons.settings_outlined,
  'folder': QuarkIcons.folder_rounded,
  'photo': QuarkIcons.photo_library_outlined,
  'health': QuarkIcons.monitor_heart_outlined,
  'home': QuarkIcons.home_filled,
  'star': QuarkIcons.star,
  'info': QuarkIcons.info_outline,
  'check': QuarkIcons.check_circle_outline,
  'warning': QuarkIcons.warning_amber,
  'error': QuarkIcons.error_outline,
};
