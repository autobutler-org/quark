import 'dart:convert';
import 'dart:typed_data';

/// What a vault item is: a login entry, or a folder entries are filed in.
enum VaultItemKind {
  /// A saved login.
  entry,

  /// A folder. Entries name it by its item id in [VaultItemData.folderId].
  folder,
}

/// A name and value the user added to an entry beyond the standard fields.
class VaultCustomField {
  /// Builds a field.
  const VaultCustomField({
    required this.label,
    required this.value,
    this.hidden = false,
  });

  /// What the field is called.
  final String label;

  /// What it holds.
  final String value;

  /// Whether the value is masked until revealed, as a password is.
  final bool hidden;

  /// Reads one field of a decrypted item.
  factory VaultCustomField.fromJson(Map<String, dynamic> json) =>
      VaultCustomField(
        label: json['label'] as String? ?? '',
        value: json['value'] as String? ?? '',
        hidden: json['hidden'] as bool? ?? false,
      );

  /// The field as it is encrypted.
  Map<String, dynamic> toJson() => {
    'label': label,
    'value': value,
    'hidden': hidden,
  };
}

/// A native Android app an entry fills (#3601): its package, and the
/// signing certificates it must carry for the entry to fill it.
class VaultAndroidApp {
  /// Builds a link.
  const VaultAndroidApp({
    required this.packageName,
    this.sha256CertFingerprints = const [],
  });

  /// The app's package name, such as `com.example.bank`.
  final String packageName;

  /// The SHA-256 fingerprints of every certificate the app is signed with,
  /// as the native service writes them.
  final List<String> sha256CertFingerprints;

  /// Reads one link of a decrypted item.
  factory VaultAndroidApp.fromJson(Map<String, dynamic> json) =>
      VaultAndroidApp(
        packageName: json['packageName'] as String? ?? '',
        sha256CertFingerprints: [
          for (final print
              in json['sha256CertFingerprints'] as List? ?? const [])
            print as String,
        ],
      );

  /// The link as it is encrypted.
  Map<String, dynamic> toJson() => {
    'packageName': packageName,
    'sha256CertFingerprints': sha256CertFingerprints,
  };
}

/// Everything one vault item holds, which is all encrypted on the client
/// (#3461): the Quark stores only the ciphertext of [toJson], and sees
/// neither the kind, the name, the folder nor any secret.
///
/// The JSON is the plaintext layout [formatVersion] names. Fields that are
/// empty are left out, and a missing field reads as empty, so a field added
/// later reads from an older item without a new version. A field this app
/// does not know, written by a newer app or the browser extension, is kept
/// in [unknownFields] and written back, so rewriting an item never drops it.
class VaultItemData {
  /// Builds an item.
  const VaultItemData({
    required this.kind,
    required this.name,
    this.url = '',
    this.username = '',
    this.password = '',
    this.notes = '',
    this.totpSecret = '',
    this.customFields = const [],
    this.folderId,
    this.androidApps = const [],
    this.unknownFields = const {},
  });

  /// A folder named [name].
  const VaultItemData.folder(this.name)
    : kind = VaultItemKind.folder,
      url = '',
      username = '',
      password = '',
      notes = '',
      totpSecret = '',
      customFields = const [],
      folderId = null,
      androidApps = const [],
      unknownFields = const {};

  /// The plaintext layout this class reads and writes, sent beside the
  /// ciphertext as `formatVersion` and bound into it as additional data.
  static const int formatVersion = 1;

  /// Entry or folder.
  final VaultItemKind kind;

  /// What the list shows.
  final String name;

  /// The site the login is for, as typed.
  final String url;

  /// The login's username or email.
  final String username;

  /// The login's password.
  final String password;

  /// Free text.
  final String notes;

  /// The base32 TOTP seed, when the login has two-factor codes.
  final String totpSecret;

  /// Extra fields.
  final List<VaultCustomField> customFields;

  /// The item id of the folder this is filed in, or null for none. A folder
  /// that has since been deleted reads as none.
  final int? folderId;

  /// The native Android apps this entry fills, each only while it is signed
  /// with the certificates its link lists.
  final List<VaultAndroidApp> androidApps;

  /// The fields of the decrypted JSON this app does not read, as they were.
  final Map<String, dynamic> unknownFields;

  /// The JSON keys this class reads; any other is kept in [unknownFields].
  static const _knownKeys = {
    'kind',
    'name',
    'url',
    'username',
    'password',
    'notes',
    'totpSecret',
    'customFields',
    'folderId',
    'androidApps',
  };

  /// This item with the given fields replaced, keeping [androidApps] and
  /// [unknownFields]. Pass [clearFolder] to file it in no folder.
  VaultItemData copyWith({
    VaultItemKind? kind,
    String? name,
    String? url,
    String? username,
    String? password,
    String? notes,
    String? totpSecret,
    List<VaultCustomField>? customFields,
    int? folderId,
    bool clearFolder = false,
    List<VaultAndroidApp>? androidApps,
  }) => VaultItemData(
    kind: kind ?? this.kind,
    name: name ?? this.name,
    url: url ?? this.url,
    username: username ?? this.username,
    password: password ?? this.password,
    notes: notes ?? this.notes,
    totpSecret: totpSecret ?? this.totpSecret,
    customFields: customFields ?? this.customFields,
    folderId: clearFolder ? null : folderId ?? this.folderId,
    androidApps: androidApps ?? this.androidApps,
    unknownFields: unknownFields,
  );

  /// [url]'s host, lowercased, or empty when it has none. A URL typed with
  /// no scheme (`example.com/login`) is read as https.
  String get urlHost => hostOf(url);

  /// The lowercased host of [url], reading a URL with no scheme as https;
  /// empty when there is none.
  static String hostOf(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final host = Uri.tryParse(withScheme)?.host ?? '';
    // Dart percent-encodes what no host may hold, such as a space.
    return host.contains('%') ? '' : host.toLowerCase();
  }

  /// Reads a decrypted item. An unknown `kind` throws a [FormatException]:
  /// it is from a newer app, and guessing would lose what it holds.
  factory VaultItemData.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'] as String? ?? VaultItemKind.entry.name;
    final kind =
        VaultItemKind.values.asNameMap()[kindName] ??
        (throw FormatException('unknown vault item kind', kindName));
    return VaultItemData(
      kind: kind,
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      totpSecret: json['totpSecret'] as String? ?? '',
      customFields: [
        for (final field in json['customFields'] as List? ?? const [])
          VaultCustomField.fromJson(field as Map<String, dynamic>),
      ],
      folderId: (json['folderId'] as num?)?.toInt(),
      androidApps: [
        for (final app in json['androidApps'] as List? ?? const [])
          VaultAndroidApp.fromJson(app as Map<String, dynamic>),
      ],
      unknownFields: {
        for (final MapEntry(:key, :value) in json.entries)
          if (!_knownKeys.contains(key)) key: value,
      },
    );
  }

  /// The item as it is encrypted.
  Map<String, dynamic> toJson() => {
    ...unknownFields,
    'kind': kind.name,
    'name': name,
    if (url.isNotEmpty) 'url': url,
    if (username.isNotEmpty) 'username': username,
    if (password.isNotEmpty) 'password': password,
    if (notes.isNotEmpty) 'notes': notes,
    if (totpSecret.isNotEmpty) 'totpSecret': totpSecret,
    if (customFields.isNotEmpty)
      'customFields': [for (final field in customFields) field.toJson()],
    'folderId': ?folderId,
    if (androidApps.isNotEmpty)
      'androidApps': [for (final app in androidApps) app.toJson()],
  };

  /// [toJson] as the UTF-8 bytes that are encrypted.
  Uint8List encode() => utf8.encode(jsonEncode(toJson()));

  /// Reads what [encode] produced.
  static VaultItemData decode(Uint8List plaintext) => VaultItemData.fromJson(
    jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
  );
}

/// A decrypted item and the id the Quark stores its ciphertext under.
class VaultItem {
  /// Pairs an id with what it holds.
  const VaultItem({required this.id, required this.data});

  /// The Quark's id for the item.
  final int id;

  /// What the item holds.
  final VaultItemData data;
}

/// One item as the Quark stores it (`/api/v0/vault/items`): ciphertext, its
/// nonce and the plaintext layout's version. Nothing else about the item
/// leaves the client.
class VaultCiphertext {
  /// Builds the stored form.
  const VaultCiphertext({
    this.id = 0,
    required this.ciphertext,
    required this.nonce,
    this.formatVersion = VaultItemData.formatVersion,
  });

  /// The Quark's id; 0 for an item not stored yet.
  final int id;

  /// XChaCha20-Poly1305 of the item's plaintext.
  final Uint8List ciphertext;

  /// Its 24-byte nonce.
  final Uint8List nonce;

  /// The plaintext layout, bound into [ciphertext] as additional data.
  final int formatVersion;

  /// Reads one item of `GET /api/v0/vault/items` and the item routes.
  factory VaultCiphertext.fromJson(Map<String, dynamic> json) =>
      VaultCiphertext(
        id: (json['id'] as num).toInt(),
        ciphertext: base64Decode(json['ciphertext'] as String),
        nonce: base64Decode(json['nonce'] as String),
        formatVersion: (json['formatVersion'] as num).toInt(),
      );

  /// The body of `POST /api/v0/vault/items` and `PUT /api/v0/vault/items/:id`.
  Map<String, dynamic> toJson() => {
    'ciphertext': base64Encode(ciphertext),
    'nonce': base64Encode(nonce),
    'formatVersion': formatVersion,
  };
}
