import 'package:flutter/material.dart';
import 'package:quark/utils/app_log.dart';
import 'package:quark/utils/clipboard_utils.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:url_launcher/url_launcher.dart';

/// The card in Settings that points at the support page and the bug tracker,
/// and copies this device's app log to paste into a report.
///
/// Both links open in the platform browser rather than in the app, since
/// neither is a Quark screen. The copy button, `help_copy_app_logs`, is
/// absent where no log is kept (the web).
class HelpSupportCard extends StatelessWidget {
  /// Creates the card. [log] is the app log to copy; a test passes its own.
  const HelpSupportCard({super.key, this.log});

  /// The log **Copy app logs** reads. Null means [AppLog.instance].
  final AppLog? log;

  /// Where Quark's help lives, in the browser.
  static const supportUrl = 'https://quark.autobutler.org/support';
  static const _bugUrl =
      'https://github.com/autobutler-org/quark/issues/new?template=bug.yaml';

  Future<void> _copyLogs(BuildContext context, AppLog log) async {
    final text = await log.read();
    if (!context.mounted) return;
    await copyToClipboard(
      context,
      text,
      message: text.isEmpty ? 'No app logs yet' : 'App logs copied',
    );
  }

  @override
  Widget build(BuildContext context) {
    final log = this.log ?? AppLog.instance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Need help or found a bug?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(supportUrl),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(QuarkIcons.help_outline, size: 16),
              label: const Text('Visit support page'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(_bugUrl),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(QuarkIcons.bug_report_outlined, size: 16),
              label: const Text('Report an issue'),
            ),
            if (log.persists) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('help_copy_app_logs'),
                onPressed: () => _copyLogs(context, log),
                icon: const Icon(QuarkIcons.content_copy, size: 16),
                label: const Text('Copy app logs'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
