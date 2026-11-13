import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the Files grouping toggle means, in words (#2037).
///
/// "Unified" and "Per-device" name the modes but explain nothing, and a
/// household owner meeting them for the first time has no way to tell what
/// either will do. Both places that offer the toggle — the wide bar's chip
/// and the compact Views menu — read their explanation from here so they
/// cannot drift apart. Their (i) help button reads its longer explanation
/// from here too (#1871).
abstract final class ViewGroupingCopy {
  /// What the unified view does.
  static const String unified = 'All your drives shown together';

  /// What the per-device view does.
  static const String perDevice = 'Each drive listed separately';

  /// The explanation for the mode currently on.
  static String forMode({required bool isUnified}) =>
      isUnified ? unified : perDevice;

  /// The title of the grouping help.
  static const String helpTitle = 'Unified and per-device views';

  /// What the grouping help explains: the two views and the device tags.
  static const List<QuarkHelpTopic> helpTopics = [
    QuarkHelpTopic(
      icon: QuarkIcons.folder_copy_outlined,
      heading: 'Unified',
      body:
          'Shows the files on all your drives together, as one library. '
          'A folder that exists on more than one drive appears once.',
    ),
    QuarkHelpTopic(
      icon: QuarkIcons.device_hub_outlined,
      heading: 'Per-device',
      body:
          'Lists each drive in its own section, so you can see what is '
          'stored where. A folder on several drives appears under each of '
          'them.',
    ),
    QuarkHelpTopic(
      icon: QuarkIcons.storage,
      heading: 'Device tags',
      body:
          'The colored tag on a file or folder names the drive it is on, and '
          'each drive keeps its own color. Hover over a tag, or press and '
          'hold it, to see the drive\'s name.',
    ),
  ];
}
