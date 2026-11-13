import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/error_banner.dart';

/// Why the terms are on screen: the Quark they are for, and that every Quark
/// asks once (#2064).
///
/// Saving a new Quark makes it the active one, and the router's gate sends an
/// active Quark with unaccepted terms straight to the terms page. Without
/// this line nothing on that page mentioned the Quark just added, so the
/// terms read as an interruption rather than the next step of adding it.
///
/// Key: `terms_host_intro`.
class TermsHostIntro extends StatelessWidget {
  /// Creates the intro for the Quark saved as [hostName].
  const TermsHostIntro({super.key, required this.hostName});

  /// The name the Quark was saved under. Empty reads as "this Quark".
  final String hostName;

  @override
  Widget build(BuildContext context) {
    return ErrorBanner(
      key: const ValueKey('terms_host_intro'),
      message:
          'Before you use ${hostName.isEmpty ? 'this Quark' : hostName}, '
          'please review and accept these terms. Every Quark asks for '
          'this the first time you connect to it.',
      tone: ErrorBannerTone.info,
    );
  }
}
