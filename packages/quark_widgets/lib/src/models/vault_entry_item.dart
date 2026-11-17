import 'package:flutter/foundation.dart';

/// One saved login as `VaultEntryList` shows it: no secret, only what the
/// row needs.
@immutable
class VaultEntryItem {
  /// Creates a row's data.
  const VaultEntryItem({
    required this.id,
    required this.name,
    this.subtitle = '',
  });

  /// Identifies the entry in callbacks and keys.
  final int id;

  /// What the row is titled.
  final String name;

  /// The line under the name, such as the site's host. Empty hides it.
  final String subtitle;
}

/// A folder entries can be filed in, as the vault widgets offer it.
@immutable
class VaultFolderItem {
  /// Creates a folder's data.
  const VaultFolderItem({required this.id, required this.name});

  /// Identifies the folder in callbacks and keys.
  final int id;

  /// What the folder is called.
  final String name;
}

/// Every field of a saved login that the vault's entry widgets show or edit.
/// `VaultEntryForm` hands one back on save.
@immutable
class VaultEntryDraft {
  /// Creates a login's fields; each defaults to empty.
  const VaultEntryDraft({
    this.name = '',
    this.url = '',
    this.username = '',
    this.password = '',
    this.notes = '',
    this.totpSecret = '',
    this.folderId,
  });

  /// What the entry is called.
  final String name;

  /// The site, as typed.
  final String url;

  /// The username or email.
  final String username;

  /// The password.
  final String password;

  /// Free text.
  final String notes;

  /// The two-factor seed. Its value is never shown, only whether there is one.
  final String totpSecret;

  /// The folder it is filed in, or null for none.
  final int? folderId;
}

/// What an entry row's menu offers, in the order it lists them.
enum VaultEntryAction {
  /// Copies the entry's password.
  copyPassword,

  /// Copies the entry's username.
  copyUsername,

  /// Opens the entry's form.
  edit,

  /// Deletes the entry, once the caller has asked.
  delete,
}
