/// The tuning and fixed values of the Locations view's map (#3557), in one
/// place rather than scattered through its widgets.
class PhotoMapConfig {
  PhotoMapConfig._();

  /// The side of one clustering cell, in screen pixels: photos whose markers
  /// would land in the same cell at the current zoom share one marker.
  static const double clusterCellPixels = 64;

  /// The zoom range the map allows. 2 shows the whole world on a phone; 18
  /// is street level, where clusters have split down to single photos.
  static const double minZoom = 2;
  static const double maxZoom = 18;

  /// The zoom the map opens at with no photo to center on, and where it
  /// centers then: the whole world.
  static const double initialZoom = 2;

  /// The zoom the map opens at centered on one photo, from the viewer's
  /// preview, and the zoom of that preview itself.
  static const double photoZoom = 14;
  static const double previewZoom = 12;

  /// The zoom the List view clusters at: cells of about a town.
  static const int listZoom = 10;

  /// The side of a marker's thumbnail. With its count badge a marker stays
  /// at least 44 px, the smallest touch target.
  static const double markerSize = 52;

  /// The height of the viewer's map preview.
  static const double previewHeight = 140;

  /// How far one arrow-key press pans the map, in screen pixels.
  static const double keyboardPanPixels = 80;

  /// The width of the wide layout's photo pane.
  static const double paneWidth = 380;

  /// Below this width the selected cluster's photos open in a bottom sheet
  /// rather than a pane beside the map.
  static const double splitBreakpoint = 840;

  /// The attribution OpenStreetMap's license requires on every map drawn
  /// from its data, the Quark's own tile pack included, and where it links.
  static const String attribution = '© OpenStreetMap contributors';
  static const String attributionUrl =
      'https://www.openstreetmap.org/copyright';

  /// OpenStreetMap's public tile servers, used only when the user opts in.
  static const String openStreetMapTiles =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// How the app names itself to a tile server it does not run, as
  /// OpenStreetMap's tile usage policy asks. Native only: a browser sends its
  /// own User-Agent.
  static const String userAgentPackageName = 'org.autobutler.quark';
}
