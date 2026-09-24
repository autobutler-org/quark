import 'package:flutter/material.dart';
import 'package:quark/services/sbom_service.dart';
import 'package:quark/widgets/settings/help_support_card.dart';
import 'package:quark/widgets/settings/sbom_expansion_tile.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The About tab of Settings (#2350): this app's version, help and the terms
/// of service, and the software bill of materials.
class SettingsAboutTab extends StatelessWidget {
  /// Creates the tab.
  const SettingsAboutTab({
    required this.appVersion,
    required this.appReleaseUrl,
    required this.onOpenReleaseNotes,
    required this.onOpenTerms,
    required this.isLoadingSbom,
    required this.sbomError,
    required this.flutterSbom,
    required this.goSbom,
    this.header,
    super.key,
  });

  /// How this app's version reads, or null where no bundle answers, which
  /// hides the row.
  final String? appVersion;

  /// Where [appVersion]'s release notes live, or null for a dev build.
  final String? appReleaseUrl;

  /// Opens release notes at the given URL.
  final ValueChanged<String> onOpenReleaseNotes;

  /// Opens the terms of service.
  final VoidCallback onOpenTerms;

  /// Whether the bill of materials is being read.
  final bool isLoadingSbom;

  /// Why part of it could not be read, one line per source, or null.
  final String? sbomError;

  /// The app's dependencies, or null when they could not be read.
  final List<FlutterPackage>? flutterSbom;

  /// The Quark's dependencies, or null when they could not be read.
  final GoSbom? goSbom;

  /// Shown above the tab's content and scrolled with it, such as the
  /// page's disconnected banner; null shows nothing.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flutterSbom = this.flutterSbom;
    final goSbom = this.goSbom;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (header != null) ...[header!, const SizedBox(height: 24)],
        const Text(
          'Quark',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        if (appVersion != null)
          // Tapping the version is the whole affordance here: a button under
          // a one-line header would outweigh the line it annotates (#1756).
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: appReleaseUrl == null
                  ? null
                  : () => onOpenReleaseNotes(appReleaseUrl!),
              child: Text(
                appVersion!,
                style: appReleaseUrl == null
                    ? theme.textTheme.bodySmall
                    : theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: theme.colorScheme.primary,
                      ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        QuarkSection(
          title: 'Help & Support',
          icon: QuarkIcons.info_outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const HelpSupportCard(),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: const Text('Terms of Service'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenTerms,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        QuarkSection(
          title: 'Software Bill of Materials',
          icon: QuarkIcons.info_outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isLoadingSbom)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                if (sbomError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      sbomError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (flutterSbom != null)
                  SbomExpansionTile(
                    title: 'Flutter dependencies',
                    subtitle: '${flutterSbom.length} packages',
                    items: [
                      for (final p in flutterSbom)
                        SbomEntry(name: p.name, version: p.version, url: p.url),
                    ],
                  ),
                const SizedBox(height: 8),
                if (goSbom != null)
                  SbomExpansionTile(
                    title: 'Go dependencies',
                    subtitle:
                        '${goSbom.dependencies.length} packages · ${goSbom.goVersion}',
                    items: [
                      for (final d in goSbom.dependencies)
                        SbomEntry(name: d.path, version: d.version),
                    ],
                  ),
                if (goSbom == null && flutterSbom == null)
                  const Text('No SBOM data available.'),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
