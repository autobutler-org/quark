import 'package:flutter/material.dart';
import 'package:quark/models/calendar_view.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Calendar page's second bar row: the span on show with previous and
/// next, then Today and the view switch.
///
/// Below `QuarkAppBarBottom.collapseBreakpoint` the switch and Today fold into
/// one chip labeled with the view on show, whose menu offers Today and the
/// four views. Titles shorten to fit a phone: "Sep 2026", "Tue, Sep 29".
/// Upcoming always starts today, so it shows its span without arrows.
///
/// Key prefixes: `calendar_prev`, `calendar_next`, `calendar_today`,
/// `bar_segment_<view>`, `app_bar_bottom_menu`, `calendar_menu_today` and
/// `calendar_menu_<view>`.
class CalendarBarBottom extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the row for [view] around [anchor].
  const CalendarBarBottom({
    required this.view,
    required this.anchor,
    required this.days,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onViewSelected,
    super.key,
  });

  /// The view on show.
  final CalendarView view;

  /// The date the view is built around.
  final DateTime anchor;

  /// The dates the view spans, for the week and Upcoming titles.
  final List<DateTime> days;

  /// Steps one span back.
  final VoidCallback onPrevious;

  /// Steps one span forward.
  final VoidCallback onNext;

  /// Returns to today, in the same view.
  final VoidCallback onToday;

  /// Switches the view, keeping the date.
  final ValueChanged<CalendarView> onViewSelected;

  /// The views in the order the switch shows them.
  static const List<CalendarView> order = [
    CalendarView.day,
    CalendarView.week,
    CalendarView.month,
    CalendarView.upcoming,
  ];

  /// The name [view] goes by, in the switch and in Settings.
  static String label(CalendarView view) => switch (view) {
    CalendarView.day => 'Day',
    CalendarView.week => 'Week',
    CalendarView.month => 'Month',
    CalendarView.upcoming => 'Upcoming',
  };

  static IconData _icon(CalendarView view) => switch (view) {
    CalendarView.day => QuarkIcons.view_day_outlined,
    CalendarView.week => QuarkIcons.view_week_outlined,
    CalendarView.month => QuarkIcons.calendar_month_outlined,
    CalendarView.upcoming => QuarkIcons.view_agenda_outlined,
  };

  static String _unit(CalendarView view) => switch (view) {
    CalendarView.day => 'day',
    CalendarView.week => 'week',
    CalendarView.month => 'month',
    CalendarView.upcoming => 'week',
  };

  @override
  Size get preferredSize => const Size.fromHeight(QuarkAppBarBottom.height);

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < QuarkAppBarBottom.collapseBreakpoint;
    final title = switch (view) {
      CalendarView.day =>
        compact
            ? CalendarLabels.dayTitleShort(anchor)
            : CalendarLabels.dayTitle(anchor),
      CalendarView.week => CalendarLabels.range(
        days.first,
        days.last,
        short: compact,
      ),
      CalendarView.month =>
        compact
            ? CalendarLabels.monthTitleShort(anchor)
            : CalendarLabels.monthTitle(anchor),
      CalendarView.upcoming => 'Next 7 days',
    };

    return QuarkAppBarBottom(
      lead: view == CalendarView.upcoming
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: tokens.foreground,
                ),
              ),
            )
          : CalendarPeriodHeader(
              title: title,
              previousTooltip: 'Previous ${_unit(view)}',
              nextTooltip: 'Next ${_unit(view)}',
              onPrevious: onPrevious,
              onNext: onNext,
            ),
      actions: [
        if (view != CalendarView.upcoming)
          QuarkBarChip(
            key: const ValueKey('calendar_today'),
            icon: QuarkIcons.today_outlined,
            label: 'Today',
            keepLabel: true,
            onPressed: onToday,
          ),
        QuarkBarSegmentedToggle(
          segments: [
            for (final v in order)
              QuarkBarSegment(id: v.slug, icon: _icon(v), label: label(v)),
          ],
          selectedId: view.slug,
          onSelected: (slug) => onViewSelected(
            CalendarView.values.firstWhere((v) => v.slug == slug),
          ),
        ),
      ],
      menuLabel: label(view),
      menuIcon: _icon(view),
      menuChildren: [
        if (view != CalendarView.upcoming)
          MenuItemButton(
            key: const ValueKey('calendar_menu_today'),
            leadingIcon: const Icon(QuarkIcons.today_outlined),
            onPressed: onToday,
            child: const Text('Today'),
          ),
        for (final v in order)
          MenuItemButton(
            key: ValueKey('calendar_menu_${v.slug}'),
            leadingIcon: Icon(v == view ? QuarkIcons.check_rounded : _icon(v)),
            onPressed: v == view ? null : () => onViewSelected(v),
            child: Text(label(v)),
          ),
      ],
    );
  }
}
