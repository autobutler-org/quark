/// Where the photo at [relPath] lives, worded for someone who has never seen
/// the Quark's storage layout (#2575): folder names joined with `›`, never a
/// slash-separated path.
///
/// On the internal drive an account's home, `users/<name>`, is dropped, so a
/// photo in `users/ux-test/photos` reads "Photos" and one at the top of the
/// home reads "Files". A group folder, `groups/<name>`, reads as the group's
/// name. A [deviceName] means the photo is on another drive, whose paths
/// start at the drive itself: the drive leads, and a `users` folder there is
/// only a folder.
String photoLocation(String relPath, {String? deviceName}) {
  final segments = relPath
      .split('/')
      .where((s) => s.isNotEmpty && s != '.')
      .toList();
  if (segments.isNotEmpty) segments.removeLast();
  if (deviceName == null && segments.length >= 2) {
    if (segments.first == 'users') {
      segments.removeRange(0, 2);
    } else if (segments.first == 'groups') {
      segments.removeAt(0);
    }
  }
  if (deviceName == null && segments.isNotEmpty && segments.first == 'photos') {
    segments.first = 'Photos';
  }
  final folder = segments.join(' › ');
  if (deviceName == null) return folder.isEmpty ? 'Files' : folder;
  return folder.isEmpty ? deviceName : '$deviceName · $folder';
}
