/// Where the Locations view's map draws its tiles from (#3557). Whichever it
/// is learns only which area is on screen, never where a photo was taken.
enum PhotoMapTiles {
  /// The Quark's own offline tile pack: no third party sees anything. The
  /// default.
  quark('quark'),

  /// OpenStreetMap's public tile servers, under their tile usage policy. Off
  /// unless the user turns it on, since it tells OpenStreetMap which area is
  /// being looked at.
  openStreetMap('openstreetmap'),

  /// A tile server the household runs, by its `{z}/{x}/{y}` URL template.
  custom('custom');

  const PhotoMapTiles(this.storageValue);

  /// How the choice is stored.
  final String storageValue;

  /// The choice [value] names, or [quark] for anything else.
  static PhotoMapTiles parse(String? value) => values.firstWhere(
    (t) => t.storageValue == value,
    orElse: () => PhotoMapTiles.quark,
  );
}
