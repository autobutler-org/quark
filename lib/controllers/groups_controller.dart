import 'package:flutter/foundation.dart';
import 'package:quark/models/group.dart';
import 'package:quark/services/groups_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

typedef ListGroupsFn = Future<List<Group>> Function();
typedef CreateGroupFn = Future<void> Function(String name);
typedef RenameGroupFn = Future<void> Function(int id, String name);
typedef DeleteGroupFn = Future<void> Function(int id);
typedef GroupMemberFn = Future<void> Function(int groupId, int userId);

/// State behind the Groups tab of the Users page (#1910): the groups on the
/// Quark, creating and renaming one through a dialog, deleting one, and
/// adding and removing members.
///
/// Service calls arrive as function parameters defaulting to [GroupsService],
/// so a test passes fakes without a mocking library. Every change lists the
/// groups again rather than trusting the Quark's answer, which leaves the
/// members out of a rename. Failures come back raw; the page turns them into
/// a sentence with `Errors`.
class GroupsController extends ChangeNotifier {
  GroupsController({
    ListGroupsFn listGroups = GroupsService.list,
    CreateGroupFn createGroup = GroupsService.create,
    RenameGroupFn renameGroup = GroupsService.rename,
    DeleteGroupFn deleteGroup = GroupsService.delete,
    GroupMemberFn addMember = GroupsService.addMember,
    GroupMemberFn removeMember = GroupsService.removeMember,
  }) : _listGroups = listGroups,
       _createGroup = createGroup,
       _renameGroup = renameGroup,
       _deleteGroup = deleteGroup,
       _addMember = addMember,
       _removeMember = removeMember;

  final ListGroupsFn _listGroups;
  final CreateGroupFn _createGroup;
  final RenameGroupFn _renameGroup;
  final DeleteGroupFn _deleteGroup;
  final GroupMemberFn _addMember;
  final GroupMemberFn _removeMember;

  List<Group> _groups = const [];
  bool _hasLoaded = false;
  bool _isLoading = false;
  Object? _error;
  bool _isSaving = false;
  Object? _saveError;
  final Set<int> _busyGroups = {};
  final Set<int> _busyMembers = {};

  /// Bumped by every load, so a slow response cannot overwrite a newer one.
  int _generation = 0;
  bool _disposed = false;

  /// Every group, in the Quark's order: `everyone` first.
  List<GroupItem> get groups => [for (final group in _groups) itemFor(group)];

  /// The group with [id], or null when there is none, for a dialog or a sheet
  /// that outlives a delete.
  GroupItem? group(int id) {
    for (final group in _groups) {
      if (group.id == id) return itemFor(group);
    }
    return null;
  }

  /// Whether a load is in flight.
  bool get isLoading => _isLoading;

  /// Whether any load has succeeded, so a refresh keeps the rows showing.
  bool get hasLoaded => _hasLoaded;

  /// Why the last load failed, or null. Raw; the page composes the copy.
  Object? get error => _error;

  /// Whether a new name is being saved, by [create] or [rename].
  bool get isSaving => _isSaving;

  /// Why the last [create] or [rename] was refused, or null. Raw; the page
  /// composes the copy, and the open dialog shows it.
  Object? get saveError => _saveError;

  /// Ids of groups with a delete in flight.
  Set<int> get busyGroupIds => Set.unmodifiable(_busyGroups);

  /// Ids of accounts being added to or removed from a group.
  Set<int> get busyMemberIds => Set.unmodifiable(_busyMembers);

  /// The package's view of [group].
  static GroupItem itemFor(Group group) => GroupItem(
    id: group.id,
    name: group.name,
    isBuiltin: group.builtin,
    members: [
      for (final member in group.members)
        PrincipalItem(
          kind: PrincipalKind.user,
          id: member.id,
          name: member.username,
        ),
    ],
  );

  /// Fetches the groups. A newer load supersedes this one.
  Future<void> load() async {
    final generation = ++_generation;
    _isLoading = true;
    _notify();
    try {
      final groups = await _listGroups();
      if (!_isCurrent(generation)) return;
      _groups = groups;
      _error = null;
      _hasLoaded = true;
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _error = error;
    } finally {
      if (_isCurrent(generation)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Creates a group named [name]. True when it was created and the list
  /// reloaded; false when [saveError] now says why not. Ignored while another
  /// name is being saved.
  Future<bool> create(String name) => _save(() => _createGroup(name));

  /// Renames the group with [id] to [name]. True when it was renamed and the
  /// list reloaded; false when [saveError] now says why not. Ignored while
  /// another name is being saved.
  Future<bool> rename(int id, String name) =>
      _save(() => _renameGroup(id, name));

  /// Forgets the last save refusal, for a dialog opened fresh.
  void clearSaveError() {
    if (_saveError == null) return;
    _saveError = null;
    notifyListeners();
  }

  /// Deletes the group with [id]. Null on success, otherwise the failure.
  Future<Object?> delete(int id) =>
      _act(_busyGroups, id, () => _deleteGroup(id));

  /// Adds the account [userId] to the group [groupId]. Null on success,
  /// otherwise the failure.
  Future<Object?> addMember(int groupId, int userId) =>
      _act(_busyMembers, userId, () => _addMember(groupId, userId));

  /// Takes the account [userId] out of the group [groupId]. Null on success,
  /// otherwise the failure.
  Future<Object?> removeMember(int groupId, int userId) =>
      _act(_busyMembers, userId, () => _removeMember(groupId, userId));

  Future<bool> _save(Future<void> Function() request) async {
    if (_isSaving) return false;
    _isSaving = true;
    _saveError = null;
    _notify();
    try {
      await request();
      await load();
      return true;
    } catch (error) {
      if (!_disposed) _saveError = error;
      return false;
    } finally {
      _isSaving = false;
      _notify();
    }
  }

  /// Runs [request] with [id] marked in [busy], one change per id at a time,
  /// and reloads when it worked.
  Future<Object?> _act(
    Set<int> busy,
    int id,
    Future<void> Function() request,
  ) async {
    if (busy.contains(id)) return null;
    busy.add(id);
    _notify();
    try {
      await request();
      await load();
      return null;
    } catch (error) {
      return error;
    } finally {
      busy.remove(id);
      _notify();
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
