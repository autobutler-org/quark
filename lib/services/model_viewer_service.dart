import 'package:flutter/foundation.dart';
import 'package:quark/utils/model_viewer_config.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Reads 3D model files for the model viewer (#2988) off the UI isolate.
///
/// The bytes come through `CodeViewerService.readRange`, which reads at most
/// the length asked for; this only parses them.
class ModelViewerService {
  ModelViewerService._();

  /// The sibling files a [format] file's [bytes] need, by name, read off
  /// the UI isolate: a `.gltf`'s JSON may be most of the file.
  static Future<List<String>> resources(
    Uint8List bytes,
    QuarkModelFormat format,
  ) => compute(_resources, (bytes: bytes, format: format));

  /// Parses [bytes] as a [format] file, with the sibling [resources] it
  /// names, within [limits] on a background isolate (inline on the web,
  /// where the time cap bounds the pause), and gives a mesh over
  /// `ModelViewerConfig.previewTriangles` the preview the viewer draws
  /// while it moves (#3231), and every mesh its measurements (#3228), so
  /// neither costs the UI isolate a frame. Throws the parser's
  /// `QuarkModelParseException` for a file it will not draw.
  static Future<QuarkModelMesh> parse(
    Uint8List bytes,
    QuarkModelFormat format,
    QuarkModelLimits limits, {
    Map<String, Uint8List> resources = const {},
  }) => compute(_parse, (
    bytes: bytes,
    format: format,
    limits: limits,
    resources: resources,
  ));

  static List<String> _resources(
    ({Uint8List bytes, QuarkModelFormat format}) job,
  ) => quarkModelResources(job.bytes, job.format);

  static QuarkModelMesh _parse(
    ({
      Uint8List bytes,
      QuarkModelFormat format,
      QuarkModelLimits limits,
      Map<String, Uint8List> resources,
    })
    job,
  ) => parseQuarkModel(
    job.bytes,
    job.format,
    limits: job.limits,
    resources: job.resources,
  ).withPreview(ModelViewerConfig.previewTriangles).withMeasurements();
}
