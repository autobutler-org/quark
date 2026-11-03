import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/models/thumbnail_probe.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/model_thumbnail_renderer.dart';
import 'package:quark/services/model_viewer_service.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/utils/model_thumbnail_config.dart';
import 'package:quark/utils/model_viewer_files.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Gives an STL, OBJ or PLY the thumbnail the Quark cannot draw for it
/// (#3227), at the two moments the client has the model in hand.
///
/// - [renderForUpload] draws one for a file about to be uploaded, which
///   then travels with it through the client thumbnail path (#2379). A file
///   over [ModelThumbnailConfig.limits] is never read, and a draw that takes
///   longer than [uploadBudget] is dropped: the file uploads either way.
/// - [saveForOpenedModel] draws one from the mesh the viewer just parsed and
///   PUTs it, unless the Quark already serves a current one. Each file is
///   tried once a session, and one at a time.
///
/// Neither throws: a model with no thumbnail keeps its file icon.
class ModelThumbnailService {
  ModelThumbnailService({
    Future<ThumbnailProbe> Function(String path, {String? serial})? probe,
    Future<void> Function({
      required String path,
      String? serial,
      required Uint8List thumbnail,
    })?
    putThumbnail,
    Future<QuarkModelMesh> Function(
      Uint8List bytes,
      QuarkModelFormat format,
      QuarkModelLimits limits,
    )?
    parse,
    Future<Uint8List?> Function(QuarkModelMesh mesh)? render,
    Future<void> Function(String path, {String? serial})? evict,
    this.uploadBudget = ModelThumbnailConfig.uploadBudget,
  }) : _probe = probe ?? FilesService.probeThumbnail,
       _putThumbnail = putThumbnail ?? FilesService.putThumbnail,
       _parse = parse ?? _parseModel,
       _render = render ?? renderModelThumbnail,
       _evict = evict ?? _evictGridThumbnails;

  /// The app's one service.
  static final ModelThumbnailService instance = ModelThumbnailService();

  /// How long an upload waits for its thumbnail.
  final Duration uploadBudget;

  final Future<ThumbnailProbe> Function(String path, {String? serial}) _probe;
  final Future<void> Function({
    required String path,
    String? serial,
    required Uint8List thumbnail,
  })
  _putThumbnail;
  final Future<QuarkModelMesh> Function(
    Uint8List bytes,
    QuarkModelFormat format,
    QuarkModelLimits limits,
  )
  _parse;
  final Future<Uint8List?> Function(QuarkModelMesh mesh) _render;
  final Future<void> Function(String path, {String? serial}) _evict;

  /// Opened files tried this session, as `serial|path`.
  final Set<String> _tried = {};

  /// The tail of the opened-model queue: one draw at a time.
  Future<void> _queue = Future.value();

  /// The thumbnail of the model [name] about to be uploaded, or null when it
  /// is not a model, is over the caps, or cannot be drawn within
  /// [uploadBudget]. [length] is asked first, and [read] only for a file
  /// under the cap.
  Future<Uint8List?> renderForUpload({
    required String name,
    required Future<int> Function() length,
    required Future<Uint8List> Function() read,
  }) async {
    final format = modelFormatForName(name);
    if (!wantsModelThumbnail(name) || format == null) return null;
    const limits = ModelThumbnailConfig.limits;
    try {
      return await () async {
        if (await length() > limits.maxBytes) return null;
        final bytes = await read();
        if (bytes.length > limits.maxBytes) return null;
        return _render(await _parse(bytes, format, limits));
      }().timeout(uploadBudget);
    } catch (e) {
      debugPrint('[model_thumbnail_service.dart] No thumbnail for $name: $e');
      return null;
    }
  }

  /// Draws and uploads the thumbnail of the model at [path], whose [mesh]
  /// the viewer has just parsed, unless the Quark already serves one.
  /// Completes once it is done or has given up.
  Future<void> saveForOpenedModel({
    required String path,
    String? serial,
    required QuarkModelMesh mesh,
  }) {
    if (!wantsModelThumbnail(path) || !_tried.add('${serial ?? ''}|$path')) {
      return Future.value();
    }
    return _queue = _queue.then((_) => _save(path, serial, mesh));
  }

  Future<void> _save(String path, String? serial, QuarkModelMesh mesh) async {
    try {
      if ((await _probe(path, serial: serial)).served) return;
      final thumbnail = await _render(mesh);
      if (thumbnail == null) return;
      await _putThumbnail(path: path, serial: serial, thumbnail: thumbnail);
      await _evict(path, serial: serial);
    } catch (e) {
      debugPrint('[model_thumbnail_service.dart] No thumbnail for $path: $e');
    }
  }

  static Future<QuarkModelMesh> _parseModel(
    Uint8List bytes,
    QuarkModelFormat format,
    QuarkModelLimits limits,
  ) => ModelViewerService.parse(bytes, format, limits);

  /// Forgets the grid's and the list's failed loads of [path], so each shows
  /// the new thumbnail when it is next built.
  static Future<void> _evictGridThumbnails(String path, {String? serial}) =>
      Future.wait([
        ThumbnailCacheManager.evict(
          FilesService.constructThumbnailUrl(path, serial: serial),
        ),
        ThumbnailCacheManager.evict(
          FilesService.constructThumbnailUrl(path, serial: serial, size: 'sm'),
        ),
      ]);
}

/// Hands the mesh the model viewer parsed for [path] to
/// [ModelThumbnailService.instance] to draw its thumbnail from, without
/// waiting for it.
void saveOpenedModelThumbnail({
  required String path,
  String? serial,
  required QuarkModelMesh mesh,
}) => unawaited(
  ModelThumbnailService.instance.saveForOpenedModel(
    path: path,
    serial: serial,
    mesh: mesh,
  ),
);
