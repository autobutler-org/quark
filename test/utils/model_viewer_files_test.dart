import 'package:flutter_test/flutter_test.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/model_viewer_files.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Which files the 3D model viewer takes (#2988), where the router sends
/// them, and the note shown when one falls back to its details.
void main() {
  test(
    'STL, OBJ, PLY, glTF and 3MF open in the model viewer, by extension',
    () {
      expect(modelFormatForName('prints/Part.STL'), QuarkModelFormat.stl);
      expect(modelFormatForName('scan.obj'), QuarkModelFormat.obj);
      expect(modelFormatForName('bunny.ply'), QuarkModelFormat.ply);
      expect(modelFormatForName('car.gltf'), QuarkModelFormat.gltf);
      expect(modelFormatForName('Car.GLB'), QuarkModelFormat.gltf);
      expect(modelFormatForName('plate.3MF'), QuarkModelFormat.threeMf);
      for (final name in ['part.fbx', 'part.step', 'stl', 'a.bin', 'a.txt']) {
        expect(opensInModelViewer(name), isFalse, reason: name);
      }
    },
  );

  test('a /view link to a model opens the model viewer', () {
    expect(viewFileRedirect('prints/part.stl', null), '/model/prints/part.stl');
    expect(
      viewFileRedirect('scans/bunny.ply', 's1'),
      '/model/scans/bunny.ply?serial=s1',
    );
    expect(viewFileRedirect('models/car.glb', null), '/model/models/car.glb');
    expect(
      viewFileRedirect('prints/plate.3mf', null),
      '/model/prints/plate.3mf',
    );
    // A format the viewer does not read stays with the generic viewer.
    expect(viewFileRedirect('models/part.fbx', null), isNull);
  });

  test('every fallback reason has its own sentence', () {
    final sentences = {
      for (final issue in QuarkModelParseIssue.values)
        Errors.modelPreview(issue),
    };
    expect(sentences, hasLength(QuarkModelParseIssue.values.length));
    for (final sentence in sentences) {
      expect(sentence, endsWith('.'));
    }
  });
}
