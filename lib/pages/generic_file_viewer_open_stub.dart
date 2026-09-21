/// The web build's stand-in for handing a file to the operating system, which a browser cannot do.
Future<String> openFileWithSystem(String path) async {
  throw UnsupportedError('openFileWithSystem is not available on web');
}
