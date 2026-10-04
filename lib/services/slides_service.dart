import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/files_route_path_utils.dart';
import 'package:quark/utils/image_header_size.dart';
import 'package:quark_slides/quark_slides.dart';

/// A picture's size in pixels, as `SlideDocumentController.insertImage`
/// takes it.
typedef SlideImageSize = ({double width, double height});

/// A picture picked on this device: its file [name], its [length] in bytes,
/// and [bytes], which opens it as a stream — read once, as it uploads.
typedef SlideImagePick = ({
  String name,
  int length,
  Stream<List<int>> Function() bytes,
});

/// A picture uploaded for a presentation: the files-relative [path] it
/// landed at and its [size], or null when its header could not be read.
typedef SlideImageUpload = ({String path, SlideImageSize? size});

/// Reads and writes `.qslide` presentations on the Quark.
///
/// A presentation is a file, as a sheet or a doc is: it is downloaded,
/// decoded with [QslideCodec], and uploaded whole over the top of itself to
/// save. Pictures put on its slides (#1158) are uploaded as files of their
/// own beside it, streamed, and their size is read from their first bytes
/// rather than by decoding them. The by-type listing that feeds the Slides page goes through
/// `FileTypeListingCache` with [fileType], like Docs and Sheets.
class SlidesService {
  SlidesService._();

  /// The `/files/by-type` type of a presentation.
  static const fileType = 'qslide';

  /// The extension every presentation file carries, dot included.
  static const extension = '.qslide';

  /// A new presentation called [title]: one title slide at the default 16:9
  /// size, the title centered on it.
  static Presentation newPresentation(String title) {
    final size = SlideSize.widescreen;
    return Presentation(
      title: title,
      size: size,
      slides: [
        Slide(
          id: 'slide1',
          elements: [
            TextBox(
              id: 'title1',
              frame: ElementFrame(
                x: size.width * 0.1,
                y: size.height * 0.35,
                width: size.width * 0.8,
                height: size.height * 0.3,
              ),
              paragraphs: [
                TextParagraph([
                  TextRun(title, bold: true, fontSize: 96),
                ], alignment: TextAlignment.center),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// [name] with [extension] on the end, unless it is there already.
  static String fileNameFor(String name) =>
      name.toLowerCase().endsWith(extension) ? name : '$name$extension';

  /// Writes a new presentation called [name] into the folder new files land
  /// in — the root for an admin, a member's home otherwise, since a member
  /// cannot write the device root (#2139) — and returns its path.
  static Future<String> create(String name) async {
    final fileName = fileNameFor(name);
    final title = fileName.substring(0, fileName.length - extension.length);
    final dir = landingPath(
      isAdmin: AppSettings.instance.isAdmin.value,
      username: AppSettings.instance.username,
    );
    final landed = await FilesService.uploadFilesFromFormData(dir, [
      _multipart(fileName, newPresentation(title)),
    ]);
    return landed.firstOrNull ?? joinPath(dir, fileName);
  }

  /// Downloads and decodes the presentation at [path]. An empty file opens as
  /// a new presentation named after it, the way an empty `.qsheet` opens as
  /// one blank sheet. A file that is not a presentation throws a
  /// [QslideFormatException].
  static Future<Presentation> load(String path, {String? serial}) async {
    final bytes = await FilesService.downloadFileBytes(path, serial: serial);
    if (bytes == null || bytes.isEmpty) {
      return newPresentation(fileNameWithoutExtension(path, extension));
    }
    return QslideCodec.decode(utf8.decode(bytes));
  }

  /// Saves [presentation] over the file at [path].
  static Future<void> save(
    String path,
    Presentation presentation, {
    String? serial,
  }) async {
    await FilesService.uploadFilesFromFormData(
      parentPath(path),
      [_multipart(path.split('/').last, presentation)],
      serial: serial,
      overwrite: true,
    );
  }

  static http.MultipartFile _multipart(
    String fileName,
    Presentation presentation,
  ) => http.MultipartFile.fromBytes(
    'files',
    utf8.encode(QslideCodec.encode(presentation)),
    filename: fileName,
  );

  /// Uploads the picture [name], [length] bytes read from [bytes], into the
  /// folder of the presentation at [presentationPath], under a free name if
  /// [name] is taken there, and returns where it landed with its size.
  ///
  /// The picture is streamed: only its first [imageHeadLimit] bytes are kept,
  /// to read its size from its header ([imageHeaderSize]). [onProgress] hears
  /// the share sent so far, from 0 to 1.
  static Future<SlideImageUpload> uploadImage(
    String presentationPath, {
    required String name,
    required Stream<List<int>> bytes,
    required int length,
    String? serial,
    void Function(double sent)? onProgress,
  }) async {
    final head = ImageHeadRecorder();
    var sent = 0;
    final counted = head.watch(bytes).map((chunk) {
      sent += chunk.length;
      if (length > 0) onProgress?.call((sent / length).clamp(0.0, 1.0));
      return chunk;
    });
    final dir = parentPath(presentationPath);
    final landed = await FilesService.uploadFilesFromFormData(
      dir,
      [http.MultipartFile('files', counted, length, filename: name)],
      serial: serial,
      keepBoth: true,
    );
    onProgress?.call(1);
    return (
      path: landed.firstOrNull ?? joinPath(dir, name),
      size: _sizeOf(head.head),
    );
  }

  /// The size of the picture at [path] on the Quark, read from a ranged
  /// download of its first [imageHeadLimit] bytes, or null when its header
  /// cannot be read. A failed request throws an [ApiException].
  static Future<SlideImageSize?> readImageSize(
    String path, {
    String? serial,
  }) async {
    final files = FilesService.instance;
    final request =
        http.Request(
            'GET',
            FilesService.constructMediaUrl(path, serial: serial),
          )
          ..headers.addAll({
            ...files.authHeaders,
            'Range': 'bytes=0-${imageHeadLimit - 1}',
          });
    final response = await files.httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw ApiException(response.statusCode, 'Failed to read the picture');
    }
    // A Quark that ignores the range sends the whole file: stop reading at
    // the limit either way.
    final head = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      head.add(chunk);
      if (head.length >= imageHeadLimit) break;
    }
    return _sizeOf(head.takeBytes());
  }

  static SlideImageSize? _sizeOf(List<int> head) {
    final size = imageHeaderSize(head);
    return size == null
        ? null
        : (width: size.width.toDouble(), height: size.height.toDouble());
  }

  /// Asks the user for a picture on this device with the platform's picker,
  /// or null when they cancel. Nothing is read here: the pick opens as a
  /// stream when it uploads.
  static Future<SlideImagePick?> pickImageFile() async {
    final file = (await FilePicker.pickFiles(type: FileType.image)).firstOrNull;
    if (file == null) return null;
    final length = await file.length();
    if (length == null) {
      throw Exception('The picker did not say how large ${file.name} is');
    }
    return (name: file.name, length: length, bytes: file.readAsByteStream);
  }
}
