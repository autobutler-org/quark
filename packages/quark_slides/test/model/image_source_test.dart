import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

/// [ImageSource]: a Quark file, an uploaded asset, or a picture still inside
/// an office package (`part:<entry>`).
void main() {
  test('part: is a package part, asset: an upload, anything else a file', () {
    expect(
      ImageSource.parse('part:ppt/media/image3.png'),
      const PackagePartImage('ppt/media/image3.png'),
    );
    expect(ImageSource.parse('asset:abc'), const UploadedAssetImage('abc'));
    expect(
      ImageSource.parse('photos/dog.jpg'),
      const QuarkFileImage('photos/dog.jpg'),
    );
    expect(ImageSource.parse('photos/part:x'), isA<QuarkFileImage>());
    expect(ImageSource.parse('/part:x'), isA<QuarkFileImage>());
    expect(ImageSource.parse('PART:x'), isA<QuarkFileImage>());
    expect(
      ImageSource.parse('asset:part:x'),
      const UploadedAssetImage('part:x'),
    );
    expect(
      ImageSource.parse('part:asset:x'),
      const PackagePartImage('asset:x'),
    );
    expect(ImageSource.parse('part:'), const PackagePartImage(''));
  });

  test('a package part round trips through its stored reference', () {
    const source = PackagePartImage('ppt/media/image3.png');
    expect(source.ref, 'part:ppt/media/image3.png');
    expect(ImageSource.parse(source.ref), source);
    expect(source.hashCode, ImageSource.parse(source.ref).hashCode);
    expect(source, isNot(const QuarkFileImage('part:ppt/media/image3.png')));
    expect(source, isNot(const UploadedAssetImage('ppt/media/image3.png')));
    expect(
      const PackagePartImage('part:nested.png').ref,
      'part:part:nested.png',
    );
    expect(
      ImageSource.parse('part:part:nested.png'),
      const PackagePartImage('part:nested.png'),
    );
  });
}
