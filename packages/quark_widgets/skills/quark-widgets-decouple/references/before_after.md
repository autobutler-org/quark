# One widget, before and after

A small favorites list. Sixty lines that fetch, hold state, and draw, all in
one `State`. Nothing about it is unusual, which is the point.

## Before

```dart
import 'package:flutter/material.dart';

import '../models/photo.dart';
import '../services/favorites_service.dart';

class FavoritesList extends StatefulWidget {
  const FavoritesList({super.key, required this.onOpen});

  final void Function(Photo photo) onOpen;

  @override
  State<FavoritesList> createState() => _FavoritesListState();
}

class _FavoritesListState extends State<FavoritesList> {
  List<Photo> _photos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final photos = await FavoritesService.list();
      setState(() => _photos = photos);
    } catch (e) {
      setState(() => _error = 'Could not load favorites: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _unfavorite(Photo photo) async {
    await FavoritesService.remove(photo.id);
    setState(() => _photos.remove(photo));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: QuarkLoader());
    if (_error != null) return Center(child: Text(_error!));
    if (_photos.isEmpty) return const Center(child: Text('No favorites yet'));
    return ListView(
      children: [
        for (final photo in _photos)
          ListTile(
            title: Text(photo.name),
            onTap: () => widget.onOpen(photo),
            trailing: IconButton(
              icon: const Icon(Icons.star),
              onPressed: () => _unfavorite(photo),
            ),
          ),
      ],
    );
  }
}
```

What is wrong with it: nothing here can be tested without an HTTP client and
an auth token. The empty state cannot be rendered on demand. `_unfavorite`
never catches, so a failed request removes the row anyway and the user sees a
lie. There are no keys, so an end-to-end script has only the name to grab, and
two photos with the same name are indistinguishable. Four `setState` calls in
`_load` are four rebuilds. And the error sentence is composed inside the
widget, so no caller can word it differently.

## After

Four files. Each one is testable on its own.

### 1. The value type, in the widget package

`packages/quark_widgets/lib/src/models/photo_item.dart`

```dart
import 'package:flutter/foundation.dart';

/// One photo as the widgets render it. No JSON, no service imports.
@immutable
class PhotoItem {
  /// Creates a photo item.
  const PhotoItem({required this.id, required this.name});

  /// Stable identity, and the suffix of every key a row emits for it.
  final String id;

  /// The file name shown on the row.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is PhotoItem && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}
```

### 2. The stateless widget, in the widget package

`packages/quark_widgets/lib/src/photos/favorites_list.dart`

```dart
import 'package:flutter/material.dart';

import '../models/photo_item.dart';

/// A list of favorited photos: data in, callbacks out.
///
/// Renders four states, chosen by its inputs and never by itself: loading,
/// error, empty, and populated. The caller decides when to load and what an
/// error says.
///
/// Key prefixes:
/// - `favorite_row_<id>` for the row
/// - `favorite_star_<id>` for the row's star button
///
/// ```dart
/// FavoritesList(
///   photos: controller.photos,
///   isLoading: controller.isLoading,
///   error: controller.error,
///   onOpen: (id) => context.push('/photos/$id'),
///   onUnfavorite: controller.unfavorite,
/// )
/// ```
class FavoritesList extends StatelessWidget {
  /// Creates a favorites list.
  const FavoritesList({
    super.key,
    required this.photos,
    this.isLoading = false,
    this.error,
    this.emptyMessage = 'No favorites yet',
    this.onOpen,
    this.onUnfavorite,
  });

  /// The photos to render, in the order they should appear.
  final List<PhotoItem> photos;

  /// Whether the caller is still fetching. The widget never decides this.
  final bool isLoading;

  /// The caller's error sentence, rendered as given. Null when there is none.
  final String? error;

  /// What to say when there is nothing, so a caller can word it differently.
  final String emptyMessage;

  /// Fires with the id of the row the user tapped.
  final ValueChanged<String>? onOpen;

  /// Fires with the id whose star was tapped. Null disables every star.
  final ValueChanged<String>? onUnfavorite;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: QuarkLoader());
    if (error != null) return Center(child: Text(error!));
    if (photos.isEmpty) return Center(child: Text(emptyMessage));
    return ListView(
      children: [
        for (final photo in photos)
          ListTile(
            key: ValueKey('favorite_row_${photo.id}'),
            title: Text(photo.name, overflow: TextOverflow.ellipsis),
            onTap: onOpen == null ? null : () => onOpen!(photo.id),
            trailing: IconButton(
              key: ValueKey('favorite_star_${photo.id}'),
              tooltip: 'Remove ${photo.name} from favorites',
              icon: const Icon(Icons.star),
              onPressed: onUnfavorite == null
                  ? null
                  : () => onUnfavorite!(photo.id),
            ),
          ),
      ],
    );
  }
}
```

### 3. The controller, in the app

`lib/controllers/favorites_controller.dart`

```dart
import 'package:flutter/foundation.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../services/favorites_service.dart';

/// Owns the favorites list and every service call behind it.
class FavoritesController extends ChangeNotifier {
  /// Creates a controller. A test passes fakes; the page passes nothing.
  FavoritesController({
    Future<List<PhotoItem>> Function() fetchFavorites = _listAsItems,
    Future<void> Function(String id) removeFavorite = FavoritesService.remove,
  }) : _fetchFavorites = fetchFavorites,
       _removeFavorite = removeFavorite;

  static Future<List<PhotoItem>> _listAsItems() async {
    final photos = await FavoritesService.list();
    // The one place an app model becomes a package value type.
    return [
      for (final photo in photos) PhotoItem(id: photo.id, name: photo.name),
    ];
  }

  final Future<List<PhotoItem>> Function() _fetchFavorites;
  final Future<void> Function(String id) _removeFavorite;

  List<PhotoItem> _photos = const [];
  bool _isLoading = false;
  Object? _error;
  int _loadToken = 0;

  /// The favorites to render.
  List<PhotoItem> get photos => _photos;

  /// Whether a load is in flight.
  bool get isLoading => _isLoading;

  /// The last failure, raw. The page turns it into copy.
  Object? get error => _error;

  /// Fetches the list. Safe to call again while one is in flight.
  Future<void> load() async {
    final token = ++_loadToken;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final fetched = await _fetchFavorites();
      if (token != _loadToken) return;
      _photos = fetched;
    } catch (e) {
      if (token != _loadToken) return;
      _error = e;
    } finally {
      if (token == _loadToken) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Removes the star on [id] and drops the row, or leaves it and records the failure.
  ///
  /// Returns false when the write failed, so the page knows to say so.
  Future<bool> unfavorite(String id) async {
    _error = null;
    try {
      await _removeFavorite(id);
      _photos = _photos.where((photo) => photo.id != id).toList();
      return true;
    } catch (e) {
      _error = e;
      return false;
    } finally {
      notifyListeners();
    }
  }
}
```

A controller test needs nothing but the fakes:

```dart
test('a failed unfavorite keeps the row and records the error', () async {
  final controller = FavoritesController(
    fetchFavorites: () async => const [PhotoItem(id: 'a', name: 'Alpha')],
    removeFavorite: (_) async => throw Exception('offline'),
  );
  await controller.load();

  expect(await controller.unfavorite('a'), isFalse);
  expect(controller.photos, hasLength(1));
  expect(controller.error, isNotNull);
});
```

### 4. The page, in the app

`lib/pages/favorites_page.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../controllers/favorites_controller.dart';
import '../utils/errors.dart';

/// The favorites screen: a controller and a composition of package widgets.
class FavoritesPage extends StatefulWidget {
  /// Creates the favorites page.
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final _controller = FavoritesController();

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unfavorite(String id) async {
    if (await _controller.unfavorite(id)) return;
    if (!mounted) return;
    // Copy and snack bars stay here, never in the widget or the controller.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(Errors.message(_controller.error))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Favorites')),
        body: FavoritesList(
          photos: _controller.photos,
          isLoading: _controller.isLoading,
          error: _controller.error == null
              ? null
              : Errors.message(_controller.error),
          onOpen: (id) => context.push('/photos/$id'),
          onUnfavorite: _unfavorite,
        ),
      ),
    );
  }
}
```

## What changed

| Before | After |
| --- | --- |
| Cannot be tested without HTTP | Controller takes fake functions; widget takes plain data |
| Empty state only reachable by emptying the server | `FavoritesList(photos: [])` |
| A failed star removal drops the row anyway | Row stays, error recorded, page says so |
| No keys | `favorite_row_<id>`, `favorite_star_<id>`, documented on the class |
| Four `setState` calls per load | Two `notifyListeners` calls, one per state change |
| Error sentence composed in the widget | Sentence built by the page through `Errors.message` |
| One 60-line file | Four files, each with one job |
