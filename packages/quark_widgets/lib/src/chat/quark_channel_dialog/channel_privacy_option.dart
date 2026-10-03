import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';

/// One answer to who can see a channel in `QuarkChannelDialog`: an icon, a
/// title, a sentence saying what it means, and a radio mark showing whether
/// it is the one picked.
///
/// Its key is the caller's, such as `channel_dialog_private`.
class ChannelPrivacyOption extends StatelessWidget {
  /// Creates the option titled [title].
  const ChannelPrivacyOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  /// The glyph beside the title.
  final IconData icon;

  /// What the option is called, such as "Private".
  final String title;

  /// What picking it means for who can see the channel.
  final String description;

  /// Whether this is the option picked.
  final bool isSelected;

  /// Called when the option is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final color = isSelected ? tokens.primary : tokens.mutedForeground;
    return Semantics(
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        child: Container(
          padding: EdgeInsets.all(tokens.spacingSm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(
              color: isSelected ? tokens.primary : tokens.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color),
              SizedBox(width: tokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        color: tokens.mutedForeground,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.spacingSm),
              Icon(
                isSelected
                    ? QuarkIcons.radio_button_checked
                    : QuarkIcons.radio_button_unchecked,
                size: 20,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
