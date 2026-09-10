import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

class SbomDependency {
  const SbomDependency({
    required this.path,
    required this.version,
    this.sum,
    this.replace,
  });

  factory SbomDependency.fromJson(Map<String, dynamic> json) {
    return SbomDependency(
      path: json['path'] as String,
      version: json['version'] as String,
      sum: json['sum'] as String?,
      replace: json['replace'] != null
          ? SbomDependency.fromJson(json['replace'] as Map<String, dynamic>)
          : null,
    );
  }

  final String path;
  final String version;
  final String? sum;
  final SbomDependency? replace;
}

class GoSbom {
  const GoSbom({
    required this.goVersion,
    required this.mainPath,
    required this.mainVersion,
    required this.dependencies,
  });

  factory GoSbom.fromJson(Map<String, dynamic> json) {
    final main = json['main'] as Map<String, dynamic>;
    final deps = (json['dependencies'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(SbomDependency.fromJson)
        .toList(growable: false);
    return GoSbom(
      goVersion: json['goVersion'] as String,
      mainPath: main['path'] as String,
      mainVersion: main['version'] as String,
      dependencies: deps,
    );
  }

  final String goVersion;
  final String mainPath;
  final String mainVersion;
  final List<SbomDependency> dependencies;
}

class FlutterPackage {
  const FlutterPackage({
    required this.name,
    required this.version,
    required this.source,
    this.url,
  });

  factory FlutterPackage.fromJson(Map<String, dynamic> json) {
    return FlutterPackage(
      name: json['name'] as String,
      version: json['version'] as String,
      source: json['source'] as String,
      url: json['url'] as String?,
    );
  }

  final String name;
  final String version;
  final String source;
  final String? url;
}

class SbomService with AuthenticatedService {
  static final SbomService _instance = SbomService._();
  SbomService._();
  static SbomService get instance => _instance;

  static Map<String, String> get _authHeaders => instance.authHeaders;

  /// Fetch Go SBOM from the backend.
  static Future<GoSbom> getGoSbom() async {
    final uri = apiBaseUri.resolve('/api/v0/sbom');
    final response = await sharedHttpClient.get(uri, headers: _authHeaders);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to load Go SBOM');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    final Object? maybeData = decoded['data'];
    final Map<String, dynamic> goSbomJson;
    if (maybeData is Map<String, dynamic>) {
      goSbomJson = maybeData;
    } else {
      goSbomJson = decoded;
    }

    try {
      return GoSbom.fromJson(goSbomJson);
    } catch (e) {
      debugPrint('[sbom_service.dart] Error: $e');
      throw Exception('Failed to parse Go SBOM response: $e');
    }
  }

  /// Load Flutter SBOM from the embedded asset.
  static Future<List<FlutterPackage>> getFlutterSbom() async {
    final assetCandidates = <String>[
      'assets/sbom_flutter.json',
      'sbom_flutter.json',
    ];

    Object? rootBundleError;
    for (final assetPath in assetCandidates) {
      try {
        final raw = await rootBundle.loadString(assetPath);
        return _parseFlutterPackages(raw);
      } catch (e) {
        debugPrint('[sbom_service.dart] Error: $e');
        rootBundleError = e;
      }
    }

    // Web builds can serve assets under /assets/assets/* depending on host setup.
    if (kIsWeb) {
      final webCandidates = <String>[
        'assets/sbom_flutter.json',
        'assets/assets/sbom_flutter.json',
      ];
      for (final relativePath in webCandidates) {
        try {
          final response = await sharedHttpClient.get(
            Uri.base.resolve(relativePath),
          );
          if (response.statusCode == 200) {
            return _parseFlutterPackages(response.body);
          }
        } catch (_) {
          // Continue trying candidates.
        }
      }
    }

    throw Exception(
      'Failed to load Flutter SBOM asset. Tried '
      '${assetCandidates.join(', ')}'
      '${kIsWeb ? ', assets/sbom_flutter.json, assets/assets/sbom_flutter.json' : ''}. '
      'Last rootBundle error: $rootBundleError',
    );
  }

  static List<FlutterPackage> _parseFlutterPackages(String rawJson) {
    final json = jsonDecode(rawJson) as Map<String, dynamic>;
    final packages = (json['packages'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(FlutterPackage.fromJson)
        .toList(growable: false);
    return packages;
  }
}
