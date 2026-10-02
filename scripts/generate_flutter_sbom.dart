// Generates assets/sbom_flutter.json from pubspec.lock.
// Run via: make generate/frontend/sbom
import 'dart:convert';
import 'dart:io';

void main() async {
  final lockFile = File('pubspec.lock');
  if (!lockFile.existsSync()) {
    stderr.writeln('pubspec.lock not found. Run flutter pub get first.');
    exit(1);
  }

  final content = lockFile.readAsStringSync();
  final packages = <Map<String, dynamic>>[];

  // Parse YAML manually — avoids pulling in a yaml dep just for codegen.
  // pubspec.lock has a well-known structure: each package block starts with
  // "  <name>:" at 2-space indent, followed by 4-space-indented key: value pairs.
  String? currentPackage;
  String? currentVersion;
  String? currentSource;
  String? currentUrl;

  for (final line in content.split('\n')) {
    // Top-level package name (2 spaces indent, ends with colon)
    final packageMatch = RegExp(r'^  (\S+):$').firstMatch(line);
    if (packageMatch != null) {
      if (currentPackage != null && currentVersion != null) {
        packages.add(
          _buildEntry(
            currentPackage,
            currentVersion,
            currentSource,
            currentUrl,
          ),
        );
      }
      currentPackage = packageMatch.group(1);
      currentVersion = null;
      currentSource = null;
      currentUrl = null;
      continue;
    }

    if (currentPackage == null) continue;

    final versionMatch = RegExp(r'^    version: "?([^"]+)"?$').firstMatch(line);
    if (versionMatch != null) {
      currentVersion = versionMatch.group(1);
      continue;
    }

    final sourceMatch = RegExp(r'^    source: (\S+)$').firstMatch(line);
    if (sourceMatch != null) {
      currentSource = sourceMatch.group(1);
      continue;
    }

    final urlMatch = RegExp(r'^      url: "?([^"]+)"?$').firstMatch(line);
    if (urlMatch != null) {
      currentUrl = urlMatch.group(1);
      continue;
    }
  }

  // Flush last package
  if (currentPackage != null && currentVersion != null) {
    packages.add(
      _buildEntry(currentPackage, currentVersion, currentSource, currentUrl),
    );
  }

  packages.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

  final outputDir = Directory('assets');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  final outputFile = File('assets/sbom_flutter.json');
  outputFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({'packages': packages}),
  );

  stdout.writeln(
    'Generated assets/sbom_flutter.json with ${packages.length} packages.',
  );
}

Map<String, dynamic> _buildEntry(
  String name,
  String? version,
  String? source,
  String? url,
) {
  final entry = <String, dynamic>{
    'name': name,
    'version': version ?? 'unknown',
    'source': source ?? 'unknown',
  };
  if (url != null) {
    entry['url'] = url;
  } else if (source == 'hosted') {
    entry['url'] = 'https://pub.dev/packages/$name';
  }
  return entry;
}
