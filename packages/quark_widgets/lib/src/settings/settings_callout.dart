import 'package:material_ui/material_ui.dart';

import '../layout/quark_section.dart';
import '../theme/quark_tokens.dart';

/// A settings block that stands on its own: a [QuarkSection] heading over
/// one card holding [child], with the token's medium spacing inside the card
/// and its large spacing under the whole block.
///
/// The gap below belongs to the callout, so a section that renders nothing
/// in some states leaves no orphaned spacing in its parent.
///
/// Key prefixes: the [QuarkSection]'s `section_<title>`. The key the caller
/// passes lands on the callout, and [child] carries its own keys.
///
/// ```dart
/// SettingsCallout(
///   title: 'Restart Quark',
///   child: FilledButton(onPressed: restart, child: const Text('Restart')),
/// );
/// ```
class SettingsCallout extends StatelessWidget {
  /// Creates a callout headed [title] around [child].
  const SettingsCallout({required this.title, required this.child, super.key});

  /// The heading above the card.
  final String title;

  /// The card's only content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacingLg),
      child: QuarkSection(
        title: title,
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingMd),
            child: child,
          ),
        ),
      ),
    );
  }
}
