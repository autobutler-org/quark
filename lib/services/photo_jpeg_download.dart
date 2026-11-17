import 'dart:typed_data';

import 'package:quark/services/client_thumbnails.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/utils/jpeg_exif.dart';

/// "Download as JPEG" for a HEIC photo (#4188): the most compatible copy,
/// for a PC, an older phone or a web form that cannot open HEIC.
///
/// The Quark has no HEIC decoder (#2382), so this device converts: it
/// fetches the original, decodes it with the platform's own decoder at full
/// size and upright, carries the EXIF (capture date, camera) over, and saves
/// `<name>.jpg`. A device that cannot decode it saves the original instead,
/// and [PhotoJpegDownload.converted] says so for the caller to explain.
///
/// The fetch, conversion and save are parameters so a test runs without a
/// Quark, a decoder or a save dialog.
///
/// api: GET /api/v0/files/download
Future<PhotoJpegDownload> downloadPhotoAsJpeg({
  required String path,
  required String? serial,
  required String name,
  Future<Uint8List> Function(String path, {String? serial}) fetch =
      FilesService.downloadOriginalBytes,
  Future<Uint8List?> Function(String name, Uint8List bytes) convert =
      convertImageToJpeg,
  Future<String?> Function(Uint8List bytes, String fileName) save =
      FilesService.saveBytesToFile,
}) async {
  final original = await fetch(path, serial: serial);
  final jpeg = await convert(name, original);
  if (jpeg == null) {
    return (
      savedAt: await save(original, name),
      fileName: name,
      converted: false,
    );
  }
  final exif = heicExif(original);
  final fileName = jpegFileName(name);
  return (
    savedAt: await save(
      exif == null ? jpeg : jpegWithExif(jpeg, exif),
      fileName,
    ),
    fileName: fileName,
    converted: true,
  );
}

/// What [downloadPhotoAsJpeg] saved: where it landed (null when the save
/// dialog was canceled), under what name, and whether it is the JPEG or,
/// because this device could not convert it, the original.
typedef PhotoJpegDownload = ({
  String? savedAt,
  String fileName,
  bool converted,
});

/// [name] with its extension replaced by `.jpg`, as the Quark names the
/// JPEGs it converts.
String jpegFileName(String name) {
  final dot = name.lastIndexOf('.');
  return '${dot <= 0 ? name : name.substring(0, dot)}.jpg';
}

/// Whether the photo [name] gets a "Download as JPEG" entry: a HEIC or
/// HEIF, the formats the other side most often cannot open.
bool offersJpegDownload(String name) =>
    heicImageExtensions.contains(fileExtension(name));
