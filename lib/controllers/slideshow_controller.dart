import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/models/slideshow_photo.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/music_service.dart';
import 'package:quark/services/photo_preview_service.dart';
import 'package:quark/services/slideshow_music_player.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';

export 'package:quark/services/slideshow_music_player.dart' show SlideshowMusic;

/// Loads the bytes of one slide.
typedef LoadSlide = Future<Uint8List?> Function(SlideshowPhoto photo);

/// Runs an in-app slideshow (#4179): which photo shows, in what order, when
/// the next one comes, whether the controls show, and the music behind it.
///
/// It takes the photos as the grid showed them and skips the videos among
/// them. Each photo shows for [intervalSeconds] once it has loaded, and the
/// one after it is loaded while it shows, so the change is instant. After
/// the last photo it starts over, as `/frame` does.
///
/// The page calls [start] once, and [dispose] when the slideshow ends, which
/// also stops the music.
class SlideshowController extends ChangeNotifier with SafeNotifier {
  SlideshowController({
    required List<SlideshowPhoto> photos,
    int startIndex = 0,
    LoadSlide loadSlide = loadQuarkSlide,
    Random? random,
    Future<List<MusicAlbum>> Function() listMusicAlbums =
        MusicService.listAlbums,
    Future<List<MusicTrack>> Function(String albumKey) listAlbumTracks =
        MusicService.listAlbumTracks,
    Uri Function(MusicTrack track)? trackUrl,
    SlideshowMusic? music,
  }) : _loadSlide = loadSlide,
       _random = random ?? Random(),
       _listMusicAlbums = listMusicAlbums,
       _listAlbumTracks = listAlbumTracks,
       _trackUrl = trackUrl ?? _mediaUrl,
       _music = music ?? VideoPlayerSlideshowMusic(),
       _photos = [
         for (final photo in photos)
           if (fileKindForName(photo.name) != FileKind.video) photo,
       ] {
    _order = [for (var i = 0; i < _photos.length; i++) i];
    // A start on a video lands on the first photo after it.
    final skipped = photos
        .take(startIndex.clamp(0, photos.length))
        .where((p) => fileKindForName(p.name) == FileKind.video)
        .length;
    _position = _photos.isEmpty
        ? 0
        : (startIndex - skipped).clamp(0, _photos.length - 1);
  }

  /// The intervals offered, in seconds.
  static const List<int> intervalChoices = [3, 5, 10, 15];

  /// How long the controls stay up after the last tap or mouse move.
  static const Duration controlsTimeout = Duration(seconds: 3);

  final LoadSlide _loadSlide;
  final Random _random;
  final Future<List<MusicAlbum>> Function() _listMusicAlbums;
  final Future<List<MusicTrack>> Function(String albumKey) _listAlbumTracks;
  final Uri Function(MusicTrack track) _trackUrl;
  final SlideshowMusic _music;

  final List<SlideshowPhoto> _photos;

  /// Indexes into [_photos] in playing order.
  late List<int> _order;
  late int _position;

  /// Loads in flight or done, by index into [_photos]: the photo showing
  /// and the one after it, nothing more.
  final Map<int, Future<Uint8List?>> _loads = {};

  bool _playing = true;
  int _interval = 5;
  bool _shuffle = false;
  bool _controlsVisible = true;
  Uint8List? _image;
  SlideshowPhoto? _shown;
  Object? _error;
  bool _loading = true;

  /// Bumped by every change of photo, so a load the user stepped past
  /// cannot land.
  int _showRequest = 0;
  Timer? _advance;
  Timer? _hideControls;

  List<MusicAlbum> _musicAlbums = const [];
  bool _musicLoading = false;
  Object? _musicError;
  MusicAlbum? _musicAlbum;

  /// The photos it plays, in the order given, without the videos.
  List<SlideshowPhoto> get photos => List.unmodifiable(_photos);

  /// How many photos the slideshow plays.
  int get count => _photos.length;

  /// The place in the playing order of the photo showing, zero-based.
  int get position => _position;

  /// The photo whose turn it is, or null with no photos.
  SlideshowPhoto? get current =>
      _photos.isEmpty ? null : _photos[_order[_position]];

  /// The photo shown now, which lags [current] while the next one loads.
  SlideshowPhoto? get shown => _shown;

  /// The bytes of [shown], or null before the first has loaded or when it
  /// failed to.
  Uint8List? get image => _image;

  /// Why the photo whose turn it is could not be loaded, or null.
  Object? get error => _error;

  /// Whether nothing has loaded yet.
  bool get isLoading => _loading && _image == null;

  /// Whether the slideshow advances on its own.
  bool get isPlaying => _playing;

  /// Seconds each photo shows.
  int get intervalSeconds => _interval;

  /// Whether the photos play in a shuffled order.
  bool get shuffle => _shuffle;

  /// Whether the controls show.
  bool get controlsVisible => _controlsVisible;

  /// Whether the Quark has music to play, which is what shows the music
  /// button.
  bool get hasMusic => _musicAlbums.isNotEmpty;

  /// The music albums to choose from.
  List<MusicAlbum> get musicAlbums => _musicAlbums;

  /// Whether the albums are still being listed.
  bool get musicLoading => _musicLoading;

  /// Why the albums could not be listed, or null.
  Object? get musicError => _musicError;

  /// The album playing, or null for none.
  MusicAlbum? get musicAlbum => _musicAlbum;

  /// Shows the first photo, and asks for the music albums.
  void start() {
    unawaited(_show());
    _scheduleHide();
    unawaited(_loadMusicAlbums());
  }

  /// Shows the next photo and restarts the countdown.
  void next() => _step(1);

  /// Shows the previous photo and restarts the countdown.
  void previous() => _step(-1);

  void _step(int by) {
    if (_photos.isEmpty) return;
    _position = (_position + by) % _photos.length;
    unawaited(_show());
  }

  /// Pauses or resumes, the music with it.
  void togglePlaying() {
    _playing = !_playing;
    if (_playing) {
      _scheduleAdvance();
      if (_musicAlbum != null) unawaited(_music.resume());
    } else {
      _advance?.cancel();
      if (_musicAlbum != null) unawaited(_music.pause());
    }
    notifyListeners();
  }

  /// Shows each photo for [seconds], counting afresh from now.
  void setInterval(int seconds) {
    _interval = seconds;
    _scheduleAdvance();
    notifyListeners();
  }

  /// Shuffles the photos, the one showing first, or goes back to the grid's
  /// order from the one showing.
  void setShuffle(bool on) {
    if (_photos.isEmpty) return;
    final showing = _order[_position];
    _shuffle = on;
    if (on) {
      final rest = [
        for (var i = 0; i < _photos.length; i++)
          if (i != showing) i,
      ]..shuffle(_random);
      _order = [showing, ...rest];
      _position = 0;
    } else {
      _order = [for (var i = 0; i < _photos.length; i++) i];
      _position = showing;
    }
    _preloadNext();
    notifyListeners();
  }

  /// Shows the controls, and hides them again after [controlsTimeout].
  void showControls() {
    _scheduleHide();
    if (_controlsVisible) return;
    _controlsVisible = true;
    notifyListeners();
  }

  /// Plays the album [albumKey] behind the slideshow, or stops the music
  /// for null. Throws what the Quark threw listing its tracks.
  Future<void> chooseMusic(String? albumKey) async {
    if (_musicAlbum != null) {
      await _music.stop();
      _musicAlbum = null;
      notifyListeners();
    }
    if (albumKey == null) return;
    final album = _musicAlbums.firstWhere((a) => a.key == albumKey);
    final tracks = await _listAlbumTracks(albumKey);
    if (isDisposed || tracks.isEmpty) return;
    _musicAlbum = album;
    notifyListeners();
    await _music.play([for (final track in tracks) _trackUrl(track)]);
    if (!_playing) await _music.pause();
  }

  Future<void> _loadMusicAlbums() async {
    _musicLoading = true;
    try {
      _musicAlbums = await _listMusicAlbums();
      _musicError = null;
    } catch (e) {
      // No music is no reason to stop the photos: the button stays hidden.
      _musicError = e;
    }
    _musicLoading = false;
    notifyListeners();
  }

  Future<void> _show() async {
    _advance?.cancel();
    final photo = current;
    if (photo == null) {
      _loading = false;
      notifyListeners();
      return;
    }
    final request = ++_showRequest;
    _loading = true;
    notifyListeners();
    Uint8List? bytes;
    Object? error;
    try {
      bytes = await _load(_order[_position]);
      if (bytes == null) error = Exception('No bytes for ${photo.id}');
    } catch (e) {
      error = e;
    }
    if (isDisposed || request != _showRequest) return;
    _loading = false;
    _shown = photo;
    _image = bytes;
    _error = error;
    // A failed load is not kept, so its turn next round asks again.
    if (error != null) _loads.remove(_order[_position]);
    _preloadNext();
    _scheduleAdvance();
    notifyListeners();
  }

  Future<Uint8List?> _load(int index) =>
      _loads[index] ??= _loadSlide(_photos[index]);

  /// Starts loading the photo after the one showing, and lets go of the
  /// rest.
  void _preloadNext() {
    if (_photos.isEmpty) return;
    final keep = {_order[_position], _order[(_position + 1) % _photos.length]};
    _loads.removeWhere((index, _) => !keep.contains(index));
    for (final index in keep) {
      // A preload's failure surfaces when its turn comes.
      unawaited(_load(index).then((_) {}, onError: (_) {}));
    }
  }

  void _scheduleAdvance() {
    _advance?.cancel();
    if (!_playing || isDisposed || _photos.length < 2) {
      return;
    }
    _advance = Timer(Duration(seconds: _interval), next);
  }

  void _scheduleHide() {
    _hideControls?.cancel();
    _hideControls = Timer(controlsTimeout, () {
      _controlsVisible = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _advance?.cancel();
    _hideControls?.cancel();
    unawaited(_music.stop());
    super.dispose();
  }

  static Uri _mediaUrl(MusicTrack track) => FilesService.constructMediaUrl(
    track.relPath,
    serial: track.serial.isEmpty ? null : track.serial,
  );
}

/// Loads a Quark photo's slide: its screen-sized preview (#4220), or, for a
/// photo the Quark cannot render one of, the photo the way the viewer opens
/// it, which covers a HEIC's stored preview and a RAW as JPEG. Null for a
/// photo on this device, which only its grid can read.
Future<Uint8List?> loadQuarkSlide(SlideshowPhoto photo) async {
  final relPath = photo.relPath;
  if (relPath == null) return null;
  final serial = photo.serial?.isEmpty ?? true ? null : photo.serial;
  try {
    return await PhotoPreviewService.downloadPreviewBytes(
      relPath,
      serial: serial,
    );
  } on ApiException catch (e) {
    if (e.statusCode != 404) rethrow;
    return FilesService.downloadFileBytes(relPath, serial: serial);
  }
}
