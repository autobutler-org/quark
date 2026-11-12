import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../layout/quark_section.dart';
import '../models/api_endpoint_item.dart';
import '../theme/quark_tokens.dart';
import 'api_endpoint_list/api_endpoint_tile.dart';

/// An API's endpoints, like the Swagger UI's: a search box, then the
/// endpoints grouped under their tags, each a row with its method, path,
/// summary and markers that expands to [expandedChild].
///
/// Filtering and expansion are the caller's: [endpoints] is already what the
/// search leaves, in the order to list them, and the groups follow the order
/// their tags first appear. Tapping a row only reports its id; the caller
/// decides which endpoint is expanded and passes its details, usually an
/// `ApiEndpointDetails`, as [expandedChild].
///
/// The list fills the space it is given, so give it a bounded height.
///
/// Key prefixes: `api_search` on the search box, `api_endpoint_<id>` on each
/// row, and `section_<tag>` on each group (see `QuarkSection.slug`).
///
/// ```dart
/// ApiEndpointList(
///   endpoints: controller.visibleEndpoints,
///   initialQuery: controller.query,
///   onSearchChanged: controller.search,
///   expandedId: controller.expanded?.id,
///   onToggle: controller.toggle,
///   expandedChild: ApiEndpointDetails(...),
/// );
/// ```
class ApiEndpointList extends StatelessWidget {
  /// Creates the list of [endpoints].
  const ApiEndpointList({
    required this.endpoints,
    required this.onSearchChanged,
    required this.onToggle,
    this.expandedId,
    this.expandedChild,
    this.initialQuery = '',
    super.key,
  });

  /// The endpoints to list, already filtered, in order.
  final List<ApiEndpointItem> endpoints;

  /// Called with the search box's text as it changes.
  final ValueChanged<String> onSearchChanged;

  /// Called with the id of the row tapped, to expand or collapse it.
  final ValueChanged<String> onToggle;

  /// The id of the expanded endpoint, or null when none is.
  final String? expandedId;

  /// What the expanded row shows under its header. Ignored when [expandedId]
  /// is null.
  final Widget? expandedChild;

  /// What the search box starts with.
  final String initialQuery;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final groups = <String, List<ApiEndpointItem>>{};
    for (final endpoint in endpoints) {
      (groups[endpoint.tag] ??= []).add(endpoint);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.all(tokens.spacingMd),
          child: TextFormField(
            key: const ValueKey('api_search'),
            initialValue: initialQuery,
            decoration: const InputDecoration(
              hintText: 'Filter by path, method, or summary',
              prefixIcon: Icon(QuarkIcons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: onSearchChanged,
          ),
        ),
        Expanded(
          child: endpoints.isEmpty
              ? const EmptyStateWidget(
                  icon: QuarkIcons.search,
                  headline: 'No matching endpoints',
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    tokens.spacingMd,
                    0,
                    tokens.spacingMd,
                    tokens.spacingMd,
                  ),
                  children: [
                    for (final MapEntry(key: tag, value: items)
                        in groups.entries)
                      Padding(
                        padding: EdgeInsets.only(bottom: tokens.spacingLg),
                        child: QuarkSection(
                          title: tag,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: tokens.spacingSm,
                            children: [
                              for (final endpoint in items)
                                ApiEndpointTile(
                                  endpoint: endpoint,
                                  expanded: endpoint.id == expandedId,
                                  onTap: () => onToggle(endpoint.id),
                                  child: endpoint.id == expandedId
                                      ? expandedChild
                                      : null,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
