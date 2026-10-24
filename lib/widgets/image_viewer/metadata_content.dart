import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/models/photo_metadata.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/photo_location.dart';
import 'package:quark/widgets/image_viewer/info_row.dart';
import 'package:quark/widgets/image_viewer/section.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:url_launcher/url_launcher.dart';

/// The metadata sections shown in the photo viewer, shared by the desktop
/// sidebar and the mobile drawer.
///
/// A photo with a GPS position gets an "Open in Maps" row
/// (`photo_info_open_in_maps`) under its coordinates.
class MetadataContent {
  static List<Widget> sections({
    required BuildContext context,
    required String name,
    required PhotoMetadata? metadata,
    required bool loading,
    required void Function(AlbumRef) onAlbumTap,
  }) {
    if (loading) {
      return const [
        Center(
          child: Padding(padding: EdgeInsets.all(32), child: QuarkLoader()),
        ),
      ];
    }

    final sections = <Widget>[];

    final exif = metadata?.exif;
    final dateTaken = exif?.dateTaken;
    final mtime = metadata?.mtime;
    final displayDate = (dateTaken ?? mtime)?.toLocal();
    if (displayDate != null) {
      sections.add(
        Section(
          title: 'Date & Time',
          children: [
            InfoRow(
              icon: QuarkIcons.calendar_today_outlined,
              value:
                  '${CalendarLabels.dayTitle(displayDate)}, ${displayDate.year}',
            ),
            InfoRow(
              icon: QuarkIcons.access_time_outlined,
              value: CalendarLabels.time(displayDate),
            ),
            if (dateTaken == null && mtime != null)
              const Padding(
                padding: EdgeInsets.only(left: 40, top: 2),
                child: Text(
                  'Estimated from file date',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
          ],
        ),
      );
    }

    if (exif?.hasLocation == true) {
      sections.add(
        Section(
          title: 'Location',
          children: [
            InfoRow(
              icon: QuarkIcons.location_on_outlined,
              value:
                  '${exif!.latitude!.toStringAsFixed(5)}, '
                  '${exif.longitude!.toStringAsFixed(5)}',
            ),
            InkWell(
              key: const ValueKey('photo_info_open_in_maps'),
              onTap: () => launchUrl(
                photoMapUri(exif.latitude!, exif.longitude!),
                mode: LaunchMode.externalApplication,
              ),
              child: const InfoRow(
                icon: QuarkIcons.open_in_new,
                value: 'Open in Maps',
                tappable: true,
              ),
            ),
          ],
        ),
      );
    }

    if (exif?.hasCameraInfo == true) {
      final rows = <Widget>[];
      final cam = exif!;
      final makeModel = [
        cam.make,
        cam.model,
      ].where((s) => s != null && s.isNotEmpty).join(' ');
      if (makeModel.isNotEmpty) {
        rows.add(
          InfoRow(icon: QuarkIcons.camera_alt_outlined, value: makeModel),
        );
      }
      if (cam.lens != null && cam.lens!.isNotEmpty) {
        rows.add(InfoRow(icon: QuarkIcons.lens_outlined, value: cam.lens!));
      }
      final settings = <String>[];
      if (cam.aperture != null) settings.add('f/${cam.aperture}');
      if (cam.shutterSpeed != null) settings.add(cam.shutterSpeed!);
      if (cam.iso != null) settings.add('ISO ${cam.iso}');
      if (settings.isNotEmpty) {
        rows.add(
          InfoRow(
            icon: QuarkIcons.tune_outlined,
            value: settings.join('  ·  '),
          ),
        );
      }
      if (cam.focalLength != null) {
        rows.add(
          InfoRow(
            icon: QuarkIcons.straighten_outlined,
            value: '${cam.focalLength} mm',
          ),
        );
      }
      if (rows.isNotEmpty) {
        sections.add(Section(title: 'Camera', children: rows));
      }
    }

    if (metadata != null) {
      final m = metadata;
      final ext = m.fileName.contains('.')
          ? m.fileName.split('.').last.toUpperCase()
          : 'FILE';
      sections.add(
        Section(
          title: 'File Info',
          children: [
            InfoRow(
              icon: QuarkIcons.insert_drive_file_outlined,
              value: m.fileName,
            ),
            InfoRow(icon: QuarkIcons.image_outlined, value: ext),
            InfoRow(
              icon: QuarkIcons.storage_outlined,
              value: StorageDevice.formatBytes(m.fileSize),
            ),
            if (m.width > 0 && m.height > 0)
              InfoRow(
                icon: QuarkIcons.photo_size_select_large_outlined,
                value: '${m.width} × ${m.height}',
              ),
          ],
        ),
      );
    }

    if (metadata != null && metadata.albums.isNotEmpty) {
      sections.add(
        Section(
          title: 'Albums',
          children: metadata.albums
              .map(
                (a) => InkWell(
                  onTap: () => onAlbumTap(a),
                  child: InfoRow(
                    icon: QuarkIcons.photo_album_outlined,
                    value: a.name,
                    tappable: true,
                  ),
                ),
              )
              .toList(),
        ),
      );
    }

    if (sections.isEmpty && !loading) {
      sections.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No metadata available',
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return sections;
  }
}
