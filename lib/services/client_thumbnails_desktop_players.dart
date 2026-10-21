import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail_platform_interface.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:quark/services/client_thumbnails_desktop.dart';
import 'package:quark/utils/client_thumbnail_config.dart';
import 'package:video_player/video_player.dart';

/// Opens [source] on the player this desktop plays video with: libmpv through
/// media_kit on Linux (see `installVideoPlaybackBackend`), AVFoundation on
/// macOS and Media Foundation on Windows through `fc_native_video_thumbnail`.
Future<DesktopVideoSession> openDesktopVideo(String source) async {
  if (Platform.isLinux) return MediaKitVideoSession.open(source);
  return NativeVideoSession(source);
}

/// A video on libmpv. The player runs without a video output, so nothing is
/// drawn; a screenshot of the paused frame is resized and re-encoded here.
class MediaKitVideoSession implements DesktopVideoSession {
  MediaKitVideoSession._(this._player);

  final Player _player;

  /// Opens [source] and waits until the player has decoded its size.
  static Future<MediaKitVideoSession> open(String source) async {
    final player = Player(
      configuration: const PlayerConfiguration(muted: true),
    );
    final session = MediaKitVideoSession._(player);
    try {
      await player.open(Media(source), play: false);
      await player.stream.width.firstWhere((w) => (w ?? 0) > 0);
      return session;
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  @override
  Future<Duration?> get duration async {
    final length = _player.state.duration;
    return length == Duration.zero ? null : length;
  }

  @override
  Future<Uint8List?> frameAt(Duration at, {required int longEdge}) async {
    await _player.seek(at);
    final shot = await _player.screenshot(format: 'image/png');
    final decoded = shot == null ? null : img.decodeImage(shot);
    if (decoded == null) return null;
    final scale =
        longEdge /
        (decoded.width > decoded.height ? decoded.width : decoded.height);
    final fitted = scale >= 1
        ? decoded
        : img.copyResize(
            decoded,
            width: (decoded.width * scale).round().clamp(1, longEdge),
            interpolation: img.Interpolation.average,
          );
    return img.encodeJpg(
      fitted,
      quality: (ClientThumbnailConfig.jpegQuality * 100).round(),
    );
  }

  @override
  Future<void> close() => _player.dispose();
}

/// A video read by the OS decoder. The frame comes from
/// `fc_native_video_thumbnail`; the length from `video_player`, which has a
/// backend on macOS and none we register on Windows, where it is unknown.
class NativeVideoSession implements DesktopVideoSession {
  NativeVideoSession(this._source);

  final String _source;

  @override
  Future<Duration?> get duration async {
    final isUrl = _source.startsWith('http');
    final controller = isUrl
        ? VideoPlayerController.networkUrl(Uri.parse(_source))
        : VideoPlayerController.file(File(_source));
    try {
      await controller.initialize();
      final length = controller.value.duration;
      return length == Duration.zero ? null : length;
    } catch (_) {
      return null;
    } finally {
      await controller.dispose();
    }
  }

  @override
  Future<Uint8List?> frameAt(Duration at, {required int longEdge}) {
    return FcNativeVideoThumbnail().saveThumbnailToBytes(
      srcFile: _source,
      srcFileUri: _source.startsWith('http'),
      width: longEdge,
      height: longEdge,
      format: 'jpeg',
      at: FcVideoThumbnailTime(
        at.inMilliseconds,
        FcVideoThumbnailTimeUnit.milliseconds,
      ),
      quality: (ClientThumbnailConfig.jpegQuality * 100).round(),
    );
  }

  @override
  Future<void> close() async {}
}
