import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/files_route_path_utils.dart';
import 'package:quark_slides/quark_slides.dart';

/// Reads and writes `.qslide` presentations on the Quark.
///
/// A presentation is a file, as a sheet or a doc is: it is downloaded,
/// decoded with [QslideCodec], and uploaded whole over the top of itself to
/// save. The by-type listing that feeds the Slides page goes through
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
}
