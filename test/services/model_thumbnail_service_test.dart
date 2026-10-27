import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/thumbnail_probe.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/services/model_thumbnail_service.dart';
import 'package:quark/utils/model_viewer_config.dart';
import 'package:quark_widgets/quark_widgets.dart';

final QuarkModelMesh triangle = QuarkModelMesh.fromTriangles(
  positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
  indices: Uint32List.fromList([0, 1, 2]),
);

final Uint8List jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF]);

/// `ModelThumbnailService` (#3227): what it reads, what it skips, and that
/// nothing it does can fail an upload or the viewer.
void main() {
  late List<String> probes;
  late List<(String, String?, Uint8List)> puts;
  late List<String> evicted;
  late List<(int, QuarkModelFormat, QuarkModelLimits)> parses;
  late List<QuarkModelMesh> renders;
  late bool served;

  setUp(() {
    probes = [];
    puts = [];
    evicted = [];
    parses = [];
    renders = [];
    served = false;
  });

  ModelThumbnailService service({
    Future<QuarkModelMesh> Function(Uint8List bytes)? parse,
    Future<Uint8List?> Function(QuarkModelMesh mesh)? render,
    Future<void> Function()? put,
    Duration uploadBudget = const Duration(seconds: 5),
  }) => ModelThumbnailService(
    probe: (path, {serial}) async {
      probes.add(path);
      return ThumbnailProbe(served: served);
    },
    putThumbnail: ({required path, serial, required thumbnail}) async {
      await put?.call();
      puts.add((path, serial, thumbnail));
    },
    parse: (bytes, format, limits) async {
      parses.add((bytes.length, format, limits));
      return parse == null ? triangle : parse(bytes);
    },
    render: (mesh) async {
      renders.add(mesh);
      return render == null ? jpeg : render(mesh);
    },
    evict: (path, {serial}) async => evicted.add(path),
    uploadBudget: uploadBudget,
  );

  group('renderForUpload', () {
    test('draws an STL, OBJ or PLY within the viewer caps', () async {
      for (final (name, format) in [
        ('part.stl', QuarkModelFormat.stl),
        ('part.OBJ', QuarkModelFormat.obj),
        ('scan.ply', QuarkModelFormat.ply),
      ]) {
        parses.clear();
        final thumbnail = await service().renderForUpload(
          name: name,
          length: () async => 3,
          read: () async => Uint8List(3),
        );
        expect(thumbnail, same(jpeg), reason: name);
        expect(parses.single.$1, 3);
        expect(parses.single.$2, format);
        expect(parses.single.$3.maxBytes, ModelViewerConfig.maxBytes);
        expect(parses.single.$3.maxTriangles, ModelViewerConfig.maxTriangles);
      }
    });

    test('never reads a file that is not a drawn model', () async {
      for (final name in ['photo.jpg', 'scene.gltf', 'box.3mf', 'notes.txt']) {
        var read = false;
        final thumbnail = await service().renderForUpload(
          name: name,
          length: () async => 3,
          read: () async {
            read = true;
            return Uint8List(3);
          },
        );
        expect(thumbnail, isNull, reason: name);
        expect(read, isFalse, reason: name);
      }
    });

    test('never reads a file over the viewer size cap', () async {
      var read = false;
      final thumbnail = await service().renderForUpload(
        name: 'huge.stl',
        length: () async => ModelViewerConfig.maxBytes + 1,
        read: () async {
          read = true;
          return Uint8List(0);
        },
      );
      expect(thumbnail, isNull);
      expect(read, isFalse);
      expect(parses, isEmpty);
    });

    test('a model the parser refuses uploads without a thumbnail', () async {
      final thumbnail =
          await service(
            parse: (_) async => throw const QuarkModelParseException(
              QuarkModelParseIssue.tooManyTriangles,
            ),
          ).renderForUpload(
            name: 'dense.stl',
            length: () async => 3,
            read: () async => Uint8List(3),
          );
      expect(thumbnail, isNull);
      expect(renders, isEmpty);
    });

    test('a draw over the budget is dropped, not waited on', () async {
      final never = Completer<Uint8List?>();
      final thumbnail =
          await service(
            render: (_) => never.future,
            uploadBudget: const Duration(milliseconds: 10),
          ).renderForUpload(
            name: 'slow.stl',
            length: () async => 3,
            read: () async => Uint8List(3),
          );
      expect(thumbnail, isNull);
    });
  });

  group('saveForOpenedModel', () {
    test('draws and uploads one the Quark does not serve yet', () async {
      await service().saveForOpenedModel(
        path: 'prints/part.stl',
        serial: 'usb1',
        mesh: triangle,
      );
      expect(probes, ['prints/part.stl']);
      expect(renders, [triangle]);
      expect(puts, [('prints/part.stl', 'usb1', jpeg)]);
      expect(evicted, ['prints/part.stl']);
    });

    test('leaves one the Quark already serves alone', () async {
      served = true;
      await service().saveForOpenedModel(path: 'part.stl', mesh: triangle);
      expect(probes, ['part.stl']);
      expect(renders, isEmpty);
      expect(puts, isEmpty);
    });

    test('tries each file once a session', () async {
      final thumbnails = service();
      await thumbnails.saveForOpenedModel(path: 'part.stl', mesh: triangle);
      await thumbnails.saveForOpenedModel(path: 'part.stl', mesh: triangle);
      await thumbnails.saveForOpenedModel(
        path: 'part.stl',
        serial: 'usb1',
        mesh: triangle,
      );
      expect(probes, ['part.stl', 'part.stl']);
      expect(puts, hasLength(2));
    });

    test('skips a glTF, which the Quark keeps no thumbnail for', () async {
      await service().saveForOpenedModel(path: 'scene.glb', mesh: triangle);
      expect(probes, isEmpty);
    });

    test('draws one model at a time', () async {
      final gate = Completer<void>();
      final thumbnails = service(put: () => gate.future);
      final first = thumbnails.saveForOpenedModel(
        path: 'a.stl',
        mesh: triangle,
      );
      final second = thumbnails.saveForOpenedModel(
        path: 'b.stl',
        mesh: triangle,
      );
      await pumpEventQueue();
      expect(probes, ['a.stl']);
      gate.complete();
      await Future.wait([first, second]);
      expect(probes, ['a.stl', 'b.stl']);
    });

    test(
      'a refused upload is swallowed, and the next model still goes',
      () async {
        var refuse = true;
        final thumbnails = service(
          put: () async {
            if (refuse) throw ApiException(403, 'read-only');
          },
        );
        await thumbnails.saveForOpenedModel(path: 'a.stl', mesh: triangle);
        refuse = false;
        await thumbnails.saveForOpenedModel(path: 'b.stl', mesh: triangle);
        expect(puts.map((p) => p.$1), ['b.stl']);
      },
    );
  });
}
