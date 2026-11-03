import 'dart:ui' show Color;

import 'package:quark/utils/client_thumbnail_config.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/utils/model_viewer_config.dart';
import 'package:quark_widgets/quark_widgets.dart'
    show QuarkModelCamera, QuarkModelLimits;

/// Size, look and caps of the thumbnails a client draws for the 3D models it
/// opens or uploads (#3227), which the Quark cannot draw itself.
abstract final class ModelThumbnailConfig {
  /// Edge of the square thumbnail. The Quark's tiers are center-cropped
  /// squares, so a square loses nothing to the crop.
  static const int edge = ClientThumbnailConfig.longEdge;

  /// JPEG quality, 0–100.
  static const int jpegQuality = 85;

  /// The viewer's caps (#2988, #3231). A file over them is never read for a
  /// thumbnail and goes without one, as it goes without the viewer.
  static const QuarkModelLimits limits = ModelViewerConfig.limits;

  /// How long an upload waits for its model's thumbnail before it goes
  /// without one. The file is sent either way; opening it later draws one.
  static const Duration uploadBudget = Duration(seconds: 5);

  /// The view the thumbnail is drawn from: the viewer's opening view.
  static const QuarkModelCamera camera = QuarkModelCamera.initial;

  /// The thumbnail's backdrop, a neutral gray that reads on light and dark
  /// grids alike.
  static const Color background = Color(0xFFE6E8EB);

  /// The color of a face square to the light.
  static const Color modelColor = Color(0xFF5B7FA6);
}

/// Whether the client draws a thumbnail for the file called [name]: an STL,
/// OBJ or PLY, the formats the Quark keeps a client-drawn thumbnail for.
bool wantsModelThumbnail(String name) =>
    const {'.stl', '.obj', '.ply'}.contains(fileExtension(name));
