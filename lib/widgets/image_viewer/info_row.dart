import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// One icon-and-value row of photo metadata.
class InfoRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final bool tappable;

  const InfoRow({
    super.key,
    required this.icon,
    required this.value,
    this.tappable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: tappable
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white70,
                fontSize: 13,
              ),
            ),
          ),
          if (tappable)
            const Icon(
              QuarkIcons.chevron_right,
              size: 16,
              color: Colors.white70,
            ),
        ],
      ),
    );
  }
}
