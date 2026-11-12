import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

/// One choice in the device role dialog: a radio-styled row describing what
/// the role means.
class RoleOption extends StatelessWidget {
  const RoleOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        selected
            ? QuarkIcons.radio_button_checked
            : QuarkIcons.radio_button_unchecked,
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: onTap,
    );
  }
}
