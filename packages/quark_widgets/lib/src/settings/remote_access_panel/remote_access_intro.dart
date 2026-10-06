import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';

/// What remote access is for, in a sentence a non-technical reader can
/// follow: the heading and badge `RemoteAccessPanel` shows while remote
/// access is off.
class RemoteAccessIntro extends StatelessWidget {
  /// Creates the intro.
  const RemoteAccessIntro({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: tokens.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
          child: Icon(QuarkIcons.cloud_done_outlined, color: tokens.primary),
        ),
        SizedBox(width: tokens.spacingMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: tokens.spacingXs,
            children: [
              Text(
                'Reach your Quark from anywhere',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Open your files and photos away from home. Everything '
                'travels straight from your Quark to your devices, '
                'encrypted. Nothing is stored in the cloud.',
                style: TextStyle(color: tokens.secondaryForeground),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
