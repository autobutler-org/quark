import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The "Show more" button at the end of a music listing with more to page
/// in, a loader while the next page is on its way.
///
/// Key: `music_load_more` on the button.
class MusicLoadMoreButton extends StatelessWidget {
  /// Creates the button.
  const MusicLoadMoreButton({
    required this.isLoading,
    required this.onPressed,
    super.key,
  });

  /// Whether the next page is being fetched.
  final bool isLoading;

  /// Fetches the next page.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: isLoading
            ? const QuarkLoader(size: 20)
            : OutlinedButton(
                key: const ValueKey('music_load_more'),
                onPressed: onPressed,
                child: const Text('Show more'),
              ),
      ),
    );
  }
}
