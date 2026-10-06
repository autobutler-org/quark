import 'package:flutter/material.dart';

/// A titled group of metadata rows in the photo viewer's info panel.
class Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const Section({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
        ...children,
        const Divider(
          color: Colors.white12,
          height: 1,
          indent: 16,
          endIndent: 16,
        ),
      ],
    );
  }
}
