import 'package:quark/router.dart' show RouteTab;

/// The Calendar page's views, each at `/calendar/<slug>` (#1144).
///
/// A bare `/calendar` lands on the view chosen in Settings (#2521), held in
/// `AppSettings.defaultCalendarView`. Week comes first because the first tab
/// is where it lands until one is chosen (#2519). The page's view switch
/// lists them in its own order: Day, Week, Month, Upcoming.
enum CalendarView implements RouteTab {
  week('week'),
  day('day'),
  month('month'),
  upcoming('upcoming');

  const CalendarView(this.slug);

  @override
  final String slug;
}
