import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/models/account_keys.dart';
import 'package:quark/models/vault_item.dart';
import 'package:quark/models/vault_key.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/vault_config.dart';
import 'package:quark/utils/vault_export.dart';
import 'package:quark/utils/vault_import.dart';
import 'package:quark/utils/vault_import_summary.dart';
import 'package:quark/utils/vault_password_generator.dart';
import 'package:quark_widgets/quark_widgets.dart'
    show VaultEntryDraft, VaultEntryItem, VaultFolderItem;
import 'package:sodium/sodium_sumo.dart' show SecureKey;

/// Where the vault page stands.
enum VaultStatus {
  /// The first look at the account's vault key has not answered yet.
  loading,

  /// The account has no vault: offer to set one up.
  noVault,

  /// The account has a vault and this app has not opened it.
  locked,

  /// The vault key is open and the items are decrypted in memory.
  unlocked,

  /// The last load failed; [VaultController.error] says why.
  error,
}

/// The signed-in account's vault, decrypted on the client (#3461).
///
/// The Quark stores the vault key only wrapped ([WrappedVaultKey]) and each
/// item only as ciphertext. [setUp] makes a random vault key, wraps it under
/// the `vaultWrapKey` the login password derives over the account's auth
/// salt ([AccountCrypto.deriveAuthKeys]) and stores it, wrapped under the
/// recovery phrase too when the user typed it at setup; otherwise the
/// account's next recovery phrase rotation adds that wrap. [unlock]
/// re-derives that key from the login password: there is no separate vault
/// password. Every item is encrypted and decrypted here
/// ([AccountCrypto.encryptVaultItem]), and search, folder filtering and URL
/// matching run over the decrypted items in memory.
///
/// [lock] disposes the key and drops every decrypted item, and so does an
/// idle [autoLockAfter], a sign-out, and the vault being deleted from
/// another session. A `vault_changed` or `resync` event reads the vault
/// again.
///
/// Every collaborator is a parameter with a real default; tests pass fakes.
class VaultController extends ChangeNotifier {
  /// Builds a controller. [session] is followed so a sign-out or a switch of
  /// Quark locks the vault; the app's [instance] passes the session token.
  VaultController({
    Future<AccountCrypto> Function()? loadCrypto,
    Future<WrappedVaultKey?> Function()? fetchKey,
    Future<void> Function(WrappedVaultKey key, String authKey)? putKey,
    Future<void> Function(String authKey)? deleteVault,
    Future<List<VaultCiphertext>> Function()? listItems,
    Future<VaultCiphertext> Function(VaultCiphertext item)? createItem,
    Future<void> Function(int id, VaultCiphertext item)? updateItem,
    Future<void> Function(int id)? deleteItem,
    Future<Uint8List> Function()? authSalt,
    Stream<FileEvent>? events,
    Listenable? session,
    this.kdfParams = KdfParams.standard,
    this.autoLockAfter = VaultConfig.autoLockAfter,
  }) : _loadCrypto = loadCrypto ?? AccountCrypto.load,
       _fetchKey = fetchKey ?? VaultService.fetchKey,
       _putKey = putKey ?? VaultService.putKey,
       _deleteVault = deleteVault ?? VaultService.deleteVault,
       _listItems = listItems ?? VaultService.listItems,
       _createItem = createItem ?? VaultService.createItem,
       _updateItem = updateItem ?? VaultService.updateItem,
       _deleteItem = deleteItem ?? VaultService.deleteItem,
       _authSalt = authSalt ?? _accountAuthSalt,
       _eventStream = events,
       _session = session {
    _session?.addListener(_onSessionChanged);
  }

  /// The app's controller: the vault stays open across pages until it locks.
  static final VaultController instance = VaultController(
    session: AppSettings.instance.sessionTokenNotifier,
  );

  final Future<AccountCrypto> Function() _loadCrypto;
  final Future<WrappedVaultKey?> Function() _fetchKey;
  final Future<void> Function(WrappedVaultKey key, String authKey) _putKey;
  final Future<void> Function(String authKey) _deleteVault;
  final Future<List<VaultCiphertext>> Function() _listItems;
  final Future<VaultCiphertext> Function(VaultCiphertext item) _createItem;
  final Future<void> Function(int id, VaultCiphertext item) _updateItem;
  final Future<void> Function(int id) _deleteItem;
  final Future<Uint8List> Function() _authSalt;
  final Stream<FileEvent>? _eventStream;
  final Listenable? _session;

  /// The Argon2id cost a new vault key's wrap is derived with.
  final KdfParams kdfParams;

  /// How long the vault stays open without [touch] before it locks.
  final Duration autoLockAfter;

  AccountCrypto? _crypto;
  StreamSubscription<FileEvent>? _events;
  Timer? _autoLock;
  bool _checked = false;
  WrappedVaultKey? _stored;
  SecureKey? _key;
  List<VaultItem> _items = const [];
  Object? _error;
  bool _busy = false;
  Object? _formError;
  String _query = '';
  int? _folderId;

  /// Where the vault stands.
  VaultStatus get status {
    if (_error != null) return VaultStatus.error;
    if (!_checked) return VaultStatus.loading;
    if (_stored == null) return VaultStatus.noVault;
    return _key == null ? VaultStatus.locked : VaultStatus.unlocked;
  }

  /// Why the last [load] failed, for `Errors.message`; null otherwise.
  Object? get error => _error;

  /// Whether [setUp] or [unlock] is running.
  bool get isBusy => _busy;

  /// Why the last [setUp] or [unlock] failed, for `Errors.message`.
  Object? get formError => _formError;

  /// The search text the entries are filtered by.
  String get query => _query;

  /// The folder the entries are filtered to, or null for all.
  int? get folderId => _folderId;

  /// Every folder, by name.
  List<VaultItem> get folders => _sorted(VaultItemKind.folder);

  /// Every entry, by name.
  List<VaultItem> get entries => _sorted(VaultItemKind.entry);

  /// The entries in the chosen [folderId] whose name, URL host or username
  /// holds [query], ignoring case.
  List<VaultItem> get visibleEntries {
    final q = _query.trim().toLowerCase();
    return [
      for (final item in entries)
        if ((_folderId == null || item.data.folderId == _folderId) &&
            (q.isEmpty ||
                item.data.name.toLowerCase().contains(q) ||
                item.data.urlHost.contains(q) ||
                item.data.username.toLowerCase().contains(q)))
          item,
    ];
  }

  /// [visibleEntries] as the list's rows, subtitled by host, else username.
  List<VaultEntryItem> get visibleRows => [
    for (final item in visibleEntries)
      VaultEntryItem(
        id: item.id,
        name: item.data.name,
        subtitle: item.data.urlHost.isEmpty
            ? item.data.username
            : item.data.urlHost,
      ),
  ];

  /// [folders] as the widgets offer them.
  List<VaultFolderItem> get folderOptions => [
    for (final folder in folders)
      VaultFolderItem(id: folder.id, name: folder.data.name),
  ];

  /// Entry [id]'s fields for the entry widgets; empty when it is gone.
  VaultEntryDraft draftOf(int id) {
    final data = itemById(id)?.data;
    if (data == null) return const VaultEntryDraft();
    return VaultEntryDraft(
      name: data.name,
      url: data.url,
      username: data.username,
      password: data.password,
      notes: data.notes,
      totpSecret: data.totpSecret,
      folderId: data.folderId,
    );
  }

  /// The name of folder [id], or empty for none or a folder since deleted.
  String folderNameOf(int? id) {
    final folder = id == null ? null : itemById(id);
    return folder?.data.kind == VaultItemKind.folder ? folder!.data.name : '';
  }

  /// Saves [draft] as a new entry, or over entry [id], keeping what the
  /// draft does not carry: custom fields, Android app links and fields from
  /// a newer app (#3601). Returns the entry's id.
  Future<int> saveDraft(VaultEntryDraft draft, {int? id}) {
    final existing = id == null ? null : itemById(id)?.data;
    return save(
      (existing ?? const VaultItemData(kind: VaultItemKind.entry, name: ''))
          .copyWith(
            kind: VaultItemKind.entry,
            name: draft.name,
            url: draft.url,
            username: draft.username,
            password: draft.password,
            notes: draft.notes,
            totpSecret: draft.totpSecret,
            folderId: draft.folderId,
            clearFolder: draft.folderId == null,
          ),
      id: id,
    );
  }

  /// The item with [id], or null.
  VaultItem? itemById(int id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// The entries saved for the site at [url]: those whose host is [url]'s,
  /// or a parent domain of it, so `accounts.example.com` matches an entry for
  /// `example.com`.
  List<VaultItem> entriesForUrl(String url) {
    final host = VaultItemData.hostOf(url);
    if (host.isEmpty) return const [];
    return [
      for (final item in entries)
        if (item.data.urlHost case final entryHost
            when entryHost.isNotEmpty &&
                (host == entryHost || host.endsWith('.$entryHost')))
          item,
    ];
  }

  /// Reads the account's vault key and, while unlocked, every item again. A
  /// vault deleted from another session locks this one.
  Future<void> load() async {
    _events ??= (_eventStream ?? EventsService.instance.events).listen(
      _onEvent,
    );
    try {
      final stored = await _fetchKey();
      _stored = stored;
      _checked = true;
      if (stored == null) {
        _forget();
      } else if (_key != null) {
        await _fetchItems();
      }
      _error = null;
    } catch (e) {
      _error = e;
    }
    notifyListeners();
  }

  /// Makes the account's vault: a new random key wrapped under [password],
  /// the login password, and opens it.
  ///
  /// The Quark re-confirms [password] before it stores anything (#3461): the
  /// request carries its auth key, from the same [AccountCrypto.deriveAuthKeys]
  /// run that gives the wrap key, so one Argon2id serves both. The auth key is
  /// the only key that goes out. A 403, a password the account doesn't sign
  /// in with, sets [formError] to [Errors.vaultNotLoginPassword], and nothing
  /// is stored; so a vault is never wrapped under a password the next
  /// password change can't open.
  ///
  /// A non-empty [phrase], the account's recovery phrase, adds a phrase wrap
  /// under its `vaultWrapKey` ([AccountCrypto.deriveRecoveryKeys] normalizes
  /// it), so a recovery carries the vault over. Nothing checks the phrase: a
  /// mistyped one makes a wrap that simply never opens. Without one the key
  /// has no phrase wrap until the account's next phrase rotation adds it.
  Future<void> setUp(String password, {String phrase = ''}) =>
      _runForm(() async {
        final crypto = await _cryptoLoaded();
        final salt = await _authSalt();
        final key = crypto.generateVaultKey();
        try {
          final withPhrase = phrase.trim().isNotEmpty;
          // kdfParams is KdfParams.standard in the app: the cost every auth
          // key is derived at, so this authKey is the account's own.
          final keys = crypto.deriveAuthKeys(password, salt, kdfParams);
          final phraseKeys = withPhrase
              ? crypto.deriveRecoveryKeys(phrase, salt, kdfParams)
              : null;
          final WrappedVaultKey wrapped;
          try {
            wrapped = WrappedVaultKey(
              byPassword: crypto.wrapVaultKey(key, keys.vaultWrapKey, salt),
              byPhrase: phraseKeys == null
                  ? null
                  : crypto.wrapVaultKey(key, phraseKeys.vaultWrapKey, salt),
              kdfParams: withPhrase ? kdfParams.phraseSplit : kdfParams.split,
            );
          } finally {
            keys.dispose();
            phraseKeys?.dispose();
          }
          await _putKey(wrapped, keys.authKey);
          _stored = wrapped;
        } on ApiException catch (e) {
          key.dispose();
          if (e.statusCode == 403) {
            throw const MessageException(Errors.vaultNotLoginPassword);
          }
          // Another session made the vault first; this one unlocks it instead.
          if (e.statusCode != 409) rethrow;
          _stored = await _fetchKey();
          return;
        } catch (_) {
          key.dispose();
          rethrow;
        }
        _adopt(key, const []);
      });

  /// Opens the vault with [password], the login password. A wrong one sets
  /// [formError] to a [MessageException] carrying [Errors.vaultWrongPassword].
  Future<void> unlock(String password) => _runForm(() async {
    final stored = _stored;
    if (stored == null) return;
    final crypto = await _cryptoLoaded();
    final keys = crypto.deriveAuthKeys(
      password,
      stored.byPassword.salt,
      stored.kdfParams,
    );
    final SecureKey key;
    try {
      key = crypto.unwrapVaultKey(
        stored.byPassword,
        keys.vaultWrapKey,
        wrongSecret: Errors.vaultWrongPassword,
      );
    } finally {
      keys.dispose();
    }
    _adopt(key, const []);
    try {
      await _fetchItems();
    } catch (e) {
      _error = e;
    }
  });

  /// Forgets the vault key and every decrypted item.
  void lock() {
    _forget();
    notifyListeners();
  }

  /// Deletes the vault, its key and every item, so the account can set up a
  /// new one: the way out for a vault nothing opens any more.
  ///
  /// [password] is the login password, which the user knows even when it no
  /// longer opens the vault: after a recovery it is the new one. The Quark
  /// re-confirms its auth key, from [AccountCrypto.deriveAuthKeys] as in
  /// [setUp], before it deletes anything (#3615). A 403 throws a
  /// [MessageException] carrying [Errors.incorrectPassword], and the vault
  /// is left as it was.
  Future<void> startOver(String password) async {
    final crypto = await _cryptoLoaded();
    final keys = crypto.deriveAuthKeys(password, await _authSalt(), kdfParams);
    keys.dispose();
    try {
      await _deleteVault(keys.authKey);
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        throw const MessageException(Errors.incorrectPassword);
      }
      rethrow;
    }
    _forget();
    _stored = null;
    _formError = null;
    notifyListeners();
  }

  /// Restarts the idle timer: the user is still at the vault.
  void touch() {
    _autoLock?.cancel();
    if (_key != null) _autoLock = Timer(autoLockAfter, lock);
  }

  /// Filters the entries to those holding [text].
  void search(String text) {
    _query = text;
    touch();
    notifyListeners();
  }

  /// Filters the entries to folder [id], or all for null.
  void filterFolder(int? id) {
    _folderId = id;
    touch();
    notifyListeners();
  }

  /// Encrypts [data] and stores it: as a new item, or over item [id].
  /// Returns the item's id.
  Future<int> save(VaultItemData data, {int? id}) async {
    final sealed = _seal(data);
    final saved = id == null
        ? (await _createItem(sealed)).id
        : await _updateItem(id, sealed).then((_) => id);
    _items = [
      for (final item in _items)
        if (item.id != saved) item,
      VaultItem(id: saved, data: data),
    ];
    touch();
    notifyListeners();
    return saved;
  }

  /// Makes a folder named [name], trimmed, and returns its id. A blank name
  /// throws a [MessageException] carrying [Errors.nameBlank].
  Future<int> createFolder(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return Future.error(const MessageException(Errors.nameBlank));
    }
    return save(VaultItemData.folder(trimmed));
  }

  /// Deletes item [id]. Entries filed in a deleted folder read as in none.
  Future<void> delete(int id) async {
    _requireKey();
    await _deleteItem(id);
    _items = [
      for (final item in _items)
        if (item.id != id) item,
    ];
    if (_folderId == id) _folderId = null;
    touch();
    notifyListeners();
  }

  /// A new random password, from libsodium's secure random generator.
  String generate([PasswordOptions options = const PasswordOptions()]) {
    final crypto = _crypto;
    if (crypto == null || _key == null) {
      throw const MessageException(Errors.vaultLocked);
    }
    touch();
    return generatePassword(crypto.randomString, options);
  }

  /// Every entry in the clear, as [format].
  String export(VaultExportFormat format) {
    _requireKey();
    touch();
    return vaultExport(_items, format);
  }

  /// Imports another password manager's export [text]. An entry whose name
  /// and host, ignoring case, are already in the vault is skipped, and
  /// folders it names are made on demand.
  Future<VaultImportResult> import(String text) async {
    _requireKey();
    final parsed = parseVaultImport(text);
    String dedupKey(String name, String host) =>
        '${name.toLowerCase()}\u0000${host.toLowerCase()}';
    final seen = {
      for (final item in entries) dedupKey(item.data.name, item.data.urlHost),
    };
    final folderIds = {for (final f in folders) f.data.name: f.id};
    final errors = [...parsed.errors];
    var imported = 0;
    var skipped = 0;
    for (final e in parsed.entries) {
      final key = dedupKey(e.name, VaultItemData.hostOf(e.url));
      if (!seen.add(key)) {
        skipped++;
        continue;
      }
      try {
        final folderId = e.folder.isEmpty
            ? null
            : folderIds[e.folder] ??= await save(
                VaultItemData.folder(e.folder),
              );
        await save(
          VaultItemData(
            kind: VaultItemKind.entry,
            name: e.name,
            url: e.url,
            username: e.username,
            password: e.password,
            notes: e.notes,
            totpSecret: e.totpSecret,
            folderId: folderId,
          ),
        );
        imported++;
      } catch (err) {
        debugPrint('[vault_controller.dart] import of an entry failed: $err');
        errors.add('Could not import "${e.name}"');
      }
    }
    return (
      imported: imported,
      skipped: skipped,
      ignored: parsed.ignored,
      errors: errors,
    );
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    _events?.cancel();
    _forget();
    super.dispose();
  }

  /// [data] encrypted under the open vault key.
  VaultCiphertext _seal(VaultItemData data) {
    final key = _requireKey();
    final sealed = _crypto!.encryptVaultItem(
      data.encode(),
      key,
      formatVersion: VaultItemData.formatVersion,
    );
    return VaultCiphertext(ciphertext: sealed.ciphertext, nonce: sealed.nonce);
  }

  SecureKey _requireKey() =>
      _key ?? (throw const MessageException(Errors.vaultLocked));

  /// Lists and decrypts every item. An item that does not open, or is in a
  /// layout newer than this app's, is left out rather than failing the rest.
  Future<void> _fetchItems() async {
    final key = _key;
    final stored = await _listItems();
    // Locked, or opened again, while the list was on its way.
    if (key == null || !identical(key, _key)) return;
    final crypto = _crypto!;
    final items = <VaultItem>[];
    for (final item in stored) {
      try {
        // ponytail: a newer layout is hidden and never rewritten; read it
        // here once a second format version exists.
        if (item.formatVersion != VaultItemData.formatVersion) continue;
        final plaintext = crypto.decryptVaultItem(
          item.ciphertext,
          item.nonce,
          key,
          formatVersion: item.formatVersion,
          wrongKey: 'vault item ${item.id} does not open',
        );
        items.add(
          VaultItem(id: item.id, data: VaultItemData.decode(plaintext)),
        );
      } catch (e) {
        debugPrint('[vault_controller.dart] item ${item.id} skipped: $e');
      }
    }
    _items = items;
  }

  Future<void> _runForm(Future<void> Function() run) async {
    _busy = true;
    _formError = null;
    notifyListeners();
    try {
      await run();
    } catch (e) {
      _formError = e;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _adopt(SecureKey key, List<VaultItem> items) {
    _key?.dispose();
    _key = key;
    _items = items;
    _error = null;
    touch();
  }

  void _forget() {
    _autoLock?.cancel();
    _autoLock = null;
    _key?.dispose();
    _key = null;
    _items = const [];
    _query = '';
    _folderId = null;
  }

  List<VaultItem> _sorted(VaultItemKind kind) =>
      [
        for (final item in _items)
          if (item.data.kind == kind) item,
      ]..sort(
        (a, b) =>
            a.data.name.toLowerCase().compareTo(b.data.name.toLowerCase()),
      );

  Future<AccountCrypto> _cryptoLoaded() async =>
      _crypto ??= await _loadCrypto();

  void _onEvent(FileEvent event) {
    if (event.kind == 'vault_changed' || event.kind == 'resync') {
      if (_checked) unawaited(load());
    }
  }

  void _onSessionChanged() {
    _forget();
    _checked = false;
    _stored = null;
    _error = null;
    _formError = null;
    notifyListeners();
  }

  /// The signed-in account's auth salt, which the vault key's password wrap
  /// and the re-confirming auth key are derived over. Refused as
  /// `AuthSecret.resolve` refuses a re-confirmation: [Errors.quarkTooOld]
  /// from a Quark without auth keys, [Errors.accountTooOld] for an account
  /// with none yet. That derives only the auth key, and setup needs the wrap
  /// key from the same Argon2id run, so the salt is asked for here.
  static Future<Uint8List> _accountAuthSalt() async {
    final username =
        AppSettings.instance.username ??
        (await AuthService.checkStatus()).username;
    if (username == null) throw const UnauthorizedException();
    final answer = await AuthService.fetchAuthSalt(username);
    if (answer == null || answer.legacyRecovery == null) {
      throw const MessageException(Errors.quarkTooOld);
    }
    if (answer.legacy) throw const MessageException(Errors.accountTooOld);
    return answer.salt;
  }
}
