import 'dart:convert';

import 'package:quark/models/vault_item.dart';
import 'package:quark/utils/csv_writer.dart';

/// The two plaintext export formats the vault writes (#3461), in the shapes
/// the Quark's old `GET /vault/export` wrote, so an export from before reads
/// back through the import and one from now reads in another manager.
enum VaultExportFormat {
  /// `{"entries": [...], "folders": [...]}`, which the import reads back.
  json('quark_vault.json'),

  /// One row per entry under a `name,url,username,password,notes,totp_secret,folder` header.
  csv('quark_vault.csv');

  const VaultExportFormat(this.fileName);

  /// What the saved file is called.
  final String fileName;
}

/// Every entry in [items] as [format], with each entry's folder by name.
/// This is the one place the vault deliberately produces its secrets in the
/// clear, for a file the user asked to save.
String vaultExport(List<VaultItem> items, VaultExportFormat format) {
  final folders = {
    for (final item in items)
      if (item.data.kind == VaultItemKind.folder) item.id: item.data.name,
  };
  final entries = [
    for (final item in items)
      if (item.data.kind == VaultItemKind.entry) item.data,
  ];
  String folderOf(VaultItemData entry) => folders[entry.folderId] ?? '';
  return switch (format) {
    VaultExportFormat.json => const JsonEncoder.withIndent('  ').convert({
      'entries': [
        for (final e in entries)
          {
            'name': e.name,
            'url': e.url,
            'urlHost': e.urlHost,
            'username': e.username,
            'password': e.password,
            if (e.notes.isNotEmpty) 'notes': e.notes,
            if (e.totpSecret.isNotEmpty) 'totpSecret': e.totpSecret,
            if (e.customFields.isNotEmpty)
              'customFields': [for (final f in e.customFields) f.toJson()],
            if (folderOf(e).isNotEmpty) 'folderName': folderOf(e),
          },
      ],
      'folders': folders.values.toList(),
    }),
    VaultExportFormat.csv => csvFromRows([
      ['name', 'url', 'username', 'password', 'notes', 'totp_secret', 'folder'],
      for (final e in entries)
        [
          e.name,
          e.url,
          e.username,
          e.password,
          e.notes,
          e.totpSecret,
          folderOf(e),
        ],
    ]),
  };
}
