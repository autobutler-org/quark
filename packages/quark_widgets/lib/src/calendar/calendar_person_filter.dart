import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../layout/quark_bar_chip.dart';
import '../theme/quark_tokens.dart';

/// Whose events the calendar shows: everyone's, the signed-in person's own,
/// or, where [people] is offered, one named person's.
///
/// Three chips, the current one tinted: **Everyone**, **My events**, and a
/// person chip that opens a menu of [people] and reads the chosen name.
/// Leave [people] empty to offer only the first two, as for someone who may
/// not list the household's accounts. A narrow parent scrolls the row
/// sideways rather than overflowing.
///
/// Key prefixes: `calendar_filter_everyone`, `calendar_filter_mine`,
/// `calendar_filter_people` on the person chip, and
/// `calendar_filter_person_<name>` on each name in its menu.
///
/// ```dart
/// CalendarPersonFilter(
///   mine: filter.mine,
///   person: filter.person,
///   people: isAdmin ? usernames : const [],
///   onEveryone: () => setFilter(null),
///   onMine: () => setFilter('me'),
///   onPerson: (name) => setFilter(name),
/// );
/// ```
class CalendarPersonFilter extends StatelessWidget {
  /// Creates the filter row.
  const CalendarPersonFilter({
    required this.mine,
    required this.onEveryone,
    required this.onMine,
    this.person,
    this.people = const [],
    this.onPerson,
    super.key,
  });

  /// Whether only the signed-in person's events are shown.
  final bool mine;

  /// The one person whose events are shown, or null. Ignored while [mine].
  final String? person;

  /// The names the person chip offers, in order. Empty hides the chip.
  final List<String> people;

  /// Shows everyone's events.
  final VoidCallback onEveryone;

  /// Shows only the signed-in person's events.
  final VoidCallback onMine;

  /// Shows only the named person's events.
  final ValueChanged<String>? onPerson;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final chosen = mine ? null : person;
    final onPerson = this.onPerson;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: tokens.spacingSm,
        children: [
          QuarkBarChip(
            key: const ValueKey('calendar_filter_everyone'),
            icon: QuarkIcons.group_outlined,
            label: 'Everyone',
            keepLabel: true,
            active: !mine && chosen == null,
            onPressed: onEveryone,
          ),
          QuarkBarChip(
            key: const ValueKey('calendar_filter_mine'),
            icon: QuarkIcons.person_outline,
            label: 'My events',
            keepLabel: true,
            active: mine,
            onPressed: onMine,
          ),
          if (people.isNotEmpty && onPerson != null)
            MenuAnchor(
              menuChildren: [
                for (final name in people)
                  MenuItemButton(
                    key: ValueKey('calendar_filter_person_$name'),
                    leadingIcon: Icon(
                      name == chosen
                          ? QuarkIcons.check_rounded
                          : QuarkIcons.person_outline,
                    ),
                    onPressed: () => onPerson(name),
                    child: Text(name),
                  ),
              ],
              builder: (context, controller, _) => QuarkBarChip(
                key: const ValueKey('calendar_filter_people'),
                icon: QuarkIcons.expand_more_rounded,
                label: chosen ?? 'Person',
                tooltip: 'Show one person\'s events',
                keepLabel: true,
                active: chosen != null,
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
        ],
      ),
    );
  }
}
