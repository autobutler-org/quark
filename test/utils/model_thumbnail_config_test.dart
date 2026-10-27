import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/model_thumbnail_config.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';

/// Which files get a client-drawn 3D thumbnail (#3227), and that the Files
/// grid asks the Quark for it.
void main() {
  test('an STL, OBJ or PLY gets one, whatever its case', () {
    for (final name in ['part.stl', 'PART.STL', 'mesh.obj', 'scan.Ply']) {
      expect(wantsModelThumbnail(name), isTrue, reason: name);
    }
  });

  test('other models and files do not', () {
    for (final name in ['scene.gltf', 'scene.glb', 'box.3mf', 'a.jpg', 'stl']) {
      expect(wantsModelThumbnail(name), isFalse, reason: name);
    }
  });

  test('the grid asks the Quark for a model thumbnail', () {
    expect(hasServerThumbnail(_file('prints/part.stl')), isTrue);
    expect(hasServerThumbnail(_file('scenes/room.gltf')), isFalse);
  });
}

FileNode _file(String path) => FileNode(
  name: path.split('/').last,
  size: 1,
  isDir: false,
  deviceName: 'Internal',
  devicePath: '',
  deviceSerial: '',
  dirPath: path.substring(0, path.lastIndexOf('/')),
);
