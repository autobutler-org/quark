import 'package:flutter/material.dart';

import '../../core/quark_loader.dart';
import '../../models/remote_access_state.dart';
import '../../theme/quark_tokens.dart';

/// Remote access's [state] in a word, with a colored dot (a loader while it
/// connects) and, where there is one, a line saying what the word means.
///
/// Key prefixes: `remote_access_status_<state>`, such as
/// `remote_access_status_connecting`.
class RemoteAccessStatusLine extends StatelessWidget {
  /// Creates the line for [state].
  const RemoteAccessStatusLine({required this.state, super.key});

  /// The state to show.
  final RemoteAccessState state;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final (word, detail, color) = switch (state) {
      RemoteAccessState.off => ('Off', null, tokens.secondaryForeground),
      RemoteAccessState.connecting => (
        'Connecting…',
        'Joining its private network',
        tokens.primary,
      ),
      RemoteAccessState.on => (
        'On',
        'Reachable away from home',
        tokens.success,
      ),
      RemoteAccessState.failing => ("Couldn't connect", null, tokens.error),
    };
    final detailText = detail;
    return Column(
      key: ValueKey('remote_access_status_${state.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          spacing: tokens.spacingSm,
          children: [
            if (state == RemoteAccessState.connecting)
              const QuarkLoader(size: 14)
            else
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            Flexible(
              child: Text(
                word,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        if (detailText != null)
          Text(
            detailText,
            style: TextStyle(color: tokens.secondaryForeground, fontSize: 13),
          ),
      ],
    );
  }
}
