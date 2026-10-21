import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/vault_item.dart';

void main() {
  const linked = {
    'kind': 'entry',
    'name': 'Bank',
    'url': 'https://bank.example',
    'username': 'grace',
    'androidApps': [
      {
        'packageName': 'com.example.bank',
        'sha256CertFingerprints': ['AB:CD', '12:34'],
      },
    ],
  };

  test('reads and writes an Android app link (#3601)', () {
    final data = VaultItemData.fromJson(linked);

    final app = data.androidApps.single;
    expect(app.packageName, 'com.example.bank');
    expect(app.sha256CertFingerprints, ['AB:CD', '12:34']);
    expect(data.unknownFields, isEmpty);
    expect(VaultItemData.decode(data.encode()).toJson(), linked);
  });

  test('an entry with no link writes no androidApps key', () {
    const data = VaultItemData(kind: VaultItemKind.entry, name: 'Mail');

    expect(data.toJson(), {'kind': 'entry', 'name': 'Mail'});
  });

  test('fields from a newer app survive a round trip', () {
    final json = {
      ...linked,
      'passkeys': [
        {'rpId': 'bank.example', 'credentialId': 'abc'},
      ],
      'favorite': true,
    };

    final data = VaultItemData.decode(VaultItemData.fromJson(json).encode());

    expect(data.unknownFields.keys, ['passkeys', 'favorite']);
    expect(data.toJson(), json);
  });

  test('copyWith changes what it is given and keeps the rest', () {
    final data = VaultItemData.fromJson({
      ...linked,
      'folderId': 7,
      'customFields': [
        {'label': 'PIN', 'value': '1234', 'hidden': true},
      ],
      'favorite': true,
    });

    final edited = data.copyWith(username: 'ada');
    expect(edited.toJson(), {...data.toJson(), 'username': 'ada'});

    final noFolder = data.copyWith(clearFolder: true);
    expect(noFolder.folderId, isNull);
    expect(noFolder.androidApps.single.packageName, 'com.example.bank');
    expect(noFolder.unknownFields, {'favorite': true});
  });

  test('a known field never comes back from unknownFields', () {
    final data = VaultItemData.fromJson({
      'kind': 'entry',
      'name': 'Old',
      'password': 'secret',
    }).copyWith(password: '');

    expect(data.toJson().containsKey('password'), isFalse);
  });
}
