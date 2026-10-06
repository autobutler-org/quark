import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';

/// One reason to turn remote access on, as `RemoteAccessSetupView` lists
/// them before anything is switched on: an [icon] in a badge, a [title], and
/// a sentence of [body].
class RemoteAccessSetupPoint extends StatelessWidget {
  /// Creates the point.
  const RemoteAccessSetupPoint({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  /// The glyph in the badge.
  final IconData icon;

  /// The point, in a few words.
  final String title;

  /// What it means, in a sentence or two.
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: tokens.spacingMd,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: tokens.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(tokens.radiusMd),
          ),
          child: Icon(icon, size: 20, color: tokens.primary),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(body, style: TextStyle(color: tokens.secondaryForeground)),
            ],
          ),
        ),
      ],
    );
  }
}
