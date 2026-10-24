import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark_widgets/src/model_viewer/quark_model_parser/inflate.dart';

/// [entries] as a zip archive, each DEFLATE-compressed unless [stored].
/// [declaredSize] replaces every entry's uncompressed size in the
/// directory, the lie a zip bomb tells.
Uint8List zip(
  Map<String, Uint8List> entries, {
  bool stored = false,
  int? declaredSize,
}) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  for (final MapEntry(key: name, value: content) in entries.entries) {
    final nameBytes = utf8.encode(name);
    final data = stored
        ? content
        : Uint8List.fromList(ZLibCodec(raw: true).encode(content));
    final size = declaredSize ?? content.length;
    final offset = out.length;
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(8, stored ? 0 : 8, Endian.little)
      ..setUint32(18, data.length, Endian.little)
      ..setUint32(22, size, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    out
      ..add(local.buffer.asUint8List())
      ..add(nameBytes)
      ..add(data);
    final record = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(10, stored ? 0 : 8, Endian.little)
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, size, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(record.buffer.asUint8List())
      ..add(nameBytes);
  }
  final directoryOffset = out.length;
  final directory = central.takeBytes();
  out.add(directory);
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, directory.length, Endian.little)
    ..setUint32(16, directoryOffset, Endian.little);
  out.add(end.buffer.asUint8List());
  return out.takeBytes();
}

const String rels = '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Target="/3D/3dmodel.model" Id="rel0"
    Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>''';

/// A unit square, two triangles in the XY plane, as object [id].
String squareObject(int id) =>
    '''
    <object id="$id" type="model">
      <mesh>
        <vertices>
          <vertex x="0" y="0" z="0"/>
          <vertex x="1" y="0" z="0"/>
          <vertex x="1" y="1" z="0"/>
          <vertex x="0" y="1" z="0"/>
        </vertices>
        <triangles>
          <triangle v1="0" v2="1" v3="2"/>
          <triangle v1="0" v2="2" v3="3"/>
        </triangles>
      </mesh>
    </object>''';

/// A model part holding [resources] and building [items].
String model(String resources, String items) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<!-- written by a test -->
<model unit="millimeter" xml:lang="en-US"
    xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02"
    xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06">
  <metadata name="Title">Square &amp; co</metadata>
  <resources>$resources
  </resources>
  <build>$items
  </build>
</model>''';

/// A package whose `3D/3dmodel.model` is [modelXml], with [extra] parts.
Uint8List package(
  String modelXml, {
  Map<String, String> extra = const {},
  bool stored = false,
}) => zip({
  '[Content_Types].xml': utf8.encode('<Types/>'),
  '_rels/.rels': utf8.encode(rels),
  '3D/3dmodel.model': utf8.encode(modelXml),
  for (final MapEntry(:key, :value) in extra.entries) key: utf8.encode(value),
}, stored: stored);

final Uint8List square = package(
  model(squareObject(1), '<item objectid="1"/>'),
);

bool _startsWith(Uint8List bytes, int at, List<int> prefix) {
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[at + i] != prefix[i]) return false;
  }
  return true;
}

QuarkModelMesh parse(Uint8List bytes) =>
    parseQuarkModel(bytes, QuarkModelFormat.threeMf);

QuarkModelParseIssue? issueOf(
  Uint8List bytes, {
  QuarkModelLimits limits = const QuarkModelLimits(),
}) {
  try {
    parseQuarkModel(bytes, QuarkModelFormat.threeMf, limits: limits);
    return null;
  } on QuarkModelParseException catch (e) {
    return e.issue;
  }
}

/// `parseQuarkModel` for 3MF (#3226): the zip and its inflater, the model
/// XML, build and component transforms, parts named across the package,
/// and the files and bombs it refuses.
void main() {
  test('a deflated package draws its build item, Z-up', () {
    final mesh = parse(square);
    expect(mesh.vertexCount, 4);
    expect(mesh.triangleCount, 2);
    expect(mesh.isZUp, isTrue);
    expect(mesh.indices, [0, 1, 2, 0, 2, 3]);
    expect(mesh.min, [0, 0, 0]);
    expect(mesh.max, [1, 1, 0]);
    // Counter-clockwise from above: the normal points up.
    expect(mesh.normals.sublist(0, 3), [0, 0, 1]);
  });

  test('stored entries, and no relationships, read 3D/3dmodel.model', () {
    final bytes = zip({
      '3d/3DModel.model': utf8.encode(
        model(squareObject(1), '<item objectid="1"/>'),
      ),
    }, stored: true);
    expect(parse(bytes).triangleCount, 2);
  });

  test('the relationships name the model part, never anything outside', () {
    const custom = '''
<Relationships>
  <Relationship TargetMode="External" Target="https://example.com/x.model"
    Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
  <Relationship Target="/Models/Part%20A.model"
    Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>''';
    final bytes = zip({
      '_rels/.rels': utf8.encode(custom),
      'Models/Part A.model': utf8.encode(
        model(squareObject(7), '<item objectid="7"/>'),
      ),
    });
    expect(parse(bytes).triangleCount, 2);
  });

  test('build and component transforms compose, item after component', () {
    // Object 2 is object 1 scaled by 2 in x; the item moves it up 10.
    final mesh = parse(
      package(
        model('''${squareObject(1)}
    <object id="2" type="model">
      <components>
        <component objectid="1" transform="2 0 0 0 1 0 0 0 1 0 0 0"/>
      </components>
    </object>''', '<item objectid="2" transform="1 0 0 0 1 0 0 0 1 5 0 10"/>'),
      ),
    );
    expect(mesh.min, [5, 0, 10]);
    expect(mesh.max, [7, 1, 10]);
  });

  test('two items draw an object twice, and a mirror keeps faces out', () {
    final mesh = parse(
      package(
        model(squareObject(1), '''
    <item objectid="1"/>
    <item objectid="1" transform="1 0 0 0 1 0 0 0 -1 0 0 -3"/>'''),
      ),
    );
    expect(mesh.triangleCount, 4);
    expect(mesh.min, [0, 0, -3]);
    // The mirrored copy's corners are swapped, so its normal is the
    // mirror image of the original's rather than a copy of it.
    expect(mesh.indices.sublist(6), [4, 6, 5, 4, 7, 6]);
    expect(mesh.normals.sublist(6, 9), [0, 0, -1]);
  });

  test('a component in another part is read from the same package', () {
    final mesh = parse(
      package(
        model('''
    <object id="1" type="model">
      <components>
        <component p:path="/3D/Objects/square.model" objectid="4"
          transform="1 0 0 0 1 0 0 0 1 0 0 2"/>
      </components>
    </object>''', '<item objectid="1"/>'),
        extra: {'3D/Objects/square.model': model(squareObject(4), '')},
      ),
    );
    expect(mesh.triangleCount, 2);
    expect(mesh.min, [0, 0, 2]);
  });

  test('a package with nothing built has no surfaces', () {
    expect(
      issueOf(package(model(squareObject(1), ''))),
      QuarkModelParseIssue.noSurfaces,
    );
  });

  test('a zip bomb stops at the size cap, whatever size it declares', () {
    final padding = ' ' * (4 << 20);
    final bomb = zip({
      '3D/3dmodel.model': utf8.encode(
        model('${squareObject(1)}$padding', '<item objectid="1"/>'),
      ),
    }, declaredSize: 100);
    expect(bomb.length, lessThan(64 << 10));
    expect(
      issueOf(bomb, limits: const QuarkModelLimits(maxBytes: 1 << 20)),
      QuarkModelParseIssue.tooLarge,
    );
    // The archive and what it inflates to share the one cap.
    expect(
      issueOf(square, limits: QuarkModelLimits(maxBytes: square.length + 10)),
      QuarkModelParseIssue.tooLarge,
    );
  });

  test('the triangle and time caps hold', () {
    expect(
      issueOf(square, limits: const QuarkModelLimits(maxTriangles: 1)),
      QuarkModelParseIssue.tooManyTriangles,
    );
    // Each object holds the next twice, 30 deep: a billion squares from a
    // file of a few kilobytes.
    final nested = StringBuffer(squareObject(0));
    for (var i = 1; i <= 30; i++) {
      nested.write('''
    <object id="$i"><components>
      <component objectid="${i - 1}"/><component objectid="${i - 1}"/>
    </components></object>''');
    }
    final bytes = package(model('$nested', '<item objectid="30"/>'));
    expect(
      issueOf(
        bytes,
        limits: const QuarkModelLimits(
          maxTriangles: 1 << 30,
          maxDuration: Duration(milliseconds: 50),
        ),
      ),
      anyOf(
        QuarkModelParseIssue.tooSlow,
        QuarkModelParseIssue.tooManyTriangles,
      ),
    );
  });

  test('broken packages are malformed, never a crash', () {
    final cases = <String, Uint8List>{
      'not a zip': utf8.encode('solid nothing'),
      'truncated': Uint8List.sublistView(square, 0, square.length ~/ 2),
      'no model part': zip({'_rels/.rels': utf8.encode(rels)}),
      'not a model': package('<scene/>'),
      'a DTD': package(
        '<!DOCTYPE model [<!ENTITY a "aaaa">]>'
        '${model(squareObject(1), '<item objectid="1"/>')}',
      ),
      'an unknown object': package(
        model(squareObject(1), '<item objectid="2"/>'),
      ),
      'a vertex past the end': package(
        model(
          squareObject(1).replaceFirst('v3="3"', 'v3="4"'),
          '<item objectid="1"/>',
        ),
      ),
      'a coordinate that is not a number': package(
        model(
          squareObject(1).replaceFirst('x="1"', 'x="1mm"'),
          '<item objectid="1"/>',
        ),
      ),
      'a short transform': package(
        model(squareObject(1), '<item objectid="1" transform="1 0 0"/>'),
      ),
      'an object that holds itself': package(
        model('''
    <object id="1"><components><component objectid="1"/></components>
    </object>''', '<item objectid="1"/>'),
      ),
      'an unclosed tag': package('<model><resources><object id="1"'),
      // Never fetched.
      'a part outside the package': package(
        model('''
    <object id="1" type="model">
      <components>
        <component p:path="https://example.com/a.model" objectid="1"/>
      </components>
    </object>''', '<item objectid="1"/>'),
      ),
      'more entries than a package could need': zip({
        for (var i = 0; i < 10001; i++) 'f$i': Uint8List(0),
      }, stored: true),
      'corrupt deflate': () {
        final bytes = Uint8List.fromList(square);
        // Overwrite the start of the model's compressed data: block type 3.
        final name = utf8.encode('3D/3dmodel.model');
        var at = 0;
        while (!_startsWith(bytes, at, name)) {
          at++;
        }
        bytes.fillRange(at + name.length, at + name.length + 20, 0xff);
        return bytes;
      }(),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(issueOf(value), QuarkModelParseIssue.malformed, reason: key);
    }
  });

  group('inflate', () {
    Uint8List roundTrip(List<int> data, {int level = 6}) => inflate(
      Uint8List.fromList(ZLibCodec(raw: true, level: level).encode(data)),
      maxLength: data.length,
      tick: () {},
    );

    test('fixed, dynamic and stored blocks round-trip', () {
      final random = Random(3226);
      // Text-like bytes with repeats: dynamic codes and long matches.
      final words = [for (var i = 0; i < 64; i++) 'w$i '];
      final text = utf8.encode(
        List.generate(40000, (_) => words[random.nextInt(64)]).join(),
      );
      expect(roundTrip(text), text);
      expect(roundTrip(text, level: 0), text);
      // A few bytes get a fixed-code block.
      expect(
        roundTrip(utf8.encode('to be or not to be')),
        utf8.encode('to be or not to be'),
      );
      // Noise is stored rather than coded.
      final noise = List.generate(100000, (_) => random.nextInt(256));
      expect(roundTrip(noise, level: 9), noise);
      expect(roundTrip(const []), isEmpty);
    });

    test('output past the cap throws, whatever the input claims', () {
      final zeros = ZLibCodec(raw: true).encode(Uint8List(1 << 20));
      expect(
        () => inflate(
          Uint8List.fromList(zeros),
          maxLength: 1000,
          tick: () {},
          expectedLength: 10,
        ),
        throwsA(
          isA<QuarkModelParseException>().having(
            (e) => e.issue,
            'issue',
            QuarkModelParseIssue.tooLarge,
          ),
        ),
      );
    });
  });
}
