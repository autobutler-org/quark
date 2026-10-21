import Foundation

/// One account's ciphertext cache as the app writes it (#3596, `lib/services/vault_cache.dart`): what
/// `GET /api/v0/vault/items` returned, beside the host and username the account is labeled with. It holds no
/// plaintext and no key. The AutoFill extension (#3598) reads it from the app group container and never calls
/// the Quark (docs/design/native-autofill-vault.md, Decision 3).
public struct VaultAutofillCache: Equatable {
    /// One item's ciphertext, as the Quark listed it.
    public struct Item: Equatable {
        public let id: Int64
        public let ciphertext: [UInt8]
        public let nonce: [UInt8]
        public let formatVersion: Int

        public init(id: Int64, ciphertext: [UInt8], nonce: [UInt8], formatVersion: Int) {
            self.id = id
            self.ciphertext = ciphertext
            self.nonce = nonce
            self.formatVersion = formatVersion
        }
    }

    /// The file format this code reads, `VaultCache.schema`.
    public static let schema = 1

    /// The app group the app and the extension share, `VaultCache.appGroup`.
    public static let appGroup = "group.org.autobutler.quark"

    /// The directory the files sit in under the container's `Library/Application Support`,
    /// `VaultCache.directoryName`.
    public static let directoryName = "vault-autofill"

    private static let accountPattern = try! NSRegularExpression(pattern: "^acct_[0-9a-f]{32}$")

    /// The name the file and the account's Keychain item share, `VaultCache.accountKey`.
    public let accountKey: String
    public let host: String
    public let username: String
    /// When the app last wrote it, nil when the file does not say.
    public let syncedAt: Date?
    public let items: [Item]

    public init(accountKey: String, host: String, username: String, syncedAt: Date?, items: [Item]) {
        self.accountKey = accountKey
        self.host = host
        self.username = username
        self.syncedAt = syncedAt
        self.items = items
    }

    /// Every account's cache in `directory` that reads, in file name order. A file that does not read is left
    /// out, so it fills nothing.
    public static func load(directory: URL, fileManager: FileManager = .default) -> [VaultAutofillCache] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted().compactMap { name in
            guard name.hasSuffix(".json") else { return nil }
            let accountKey = String(name.dropLast(".json".count))
            guard let data = fileManager.contents(atPath: directory.appendingPathComponent(name).path) else {
                return nil
            }
            return decode(data, accountKey: accountKey)
        }
    }

    /// Reads one cache file. Nil for an account key `VaultCache.accountKey` would not make, a schema other than
    /// ``schema``, or anything malformed: a reader that guesses could fill from a file it does not understand.
    public static func decode(_ data: Data, accountKey: String) -> VaultAutofillCache? {
        let range = NSRange(accountKey.startIndex..., in: accountKey)
        guard accountPattern.firstMatch(in: accountKey, range: range) != nil,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["schema"] as? NSNumber)?.intValue == schema,
              let host = json["host"] as? String,
              let username = json["username"] as? String,
              let rawItems = json["items"] as? [[String: Any]]
        else { return nil }
        var items: [Item] = []
        for raw in rawItems {
            guard let id = (raw["id"] as? NSNumber)?.int64Value,
                  let ciphertext = (raw["ciphertext"] as? String).flatMap({ Data(base64Encoded: $0) }),
                  let nonce = (raw["nonce"] as? String).flatMap({ Data(base64Encoded: $0) }),
                  let formatVersion = (raw["formatVersion"] as? NSNumber)?.intValue
            else { return nil }
            items.append(Item(id: id, ciphertext: Array(ciphertext), nonce: Array(nonce), formatVersion: formatVersion))
        }
        let syncedAt = (json["syncedAt"] as? String).flatMap(parseDate)
        return VaultAutofillCache(accountKey: accountKey, host: host, username: username, syncedAt: syncedAt, items: items)
    }

    /// Dart's `toIso8601String` writes microseconds, which `ISO8601DateFormatter` does not read, so the
    /// fraction is dropped first.
    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        guard let dot = text.firstIndex(of: "."), let zone = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" })
        else { return nil }
        return formatter.date(from: String(text[..<dot]) + String(text[zone...]))
    }
}

/// A login the extension can offer: what the list shows, and never the password, which
/// ``VaultAutofill/credential(for:in:vaultKey:crypto:)`` opens only for the one the user picks.
public struct VaultAutofillEntry: Equatable {
    public let accountKey: String
    public let itemId: Int64
    public let name: String
    public let username: String
    /// The entry's site, as its `url`'s host.
    public let site: String

    public init(accountKey: String, itemId: Int64, name: String, username: String, site: String) {
        self.accountKey = accountKey
        self.itemId = itemId
        self.name = name
        self.username = username
        self.site = site
    }

    /// The identity's record identifier, `<accountKey>/<itemId>`, which QuickType identities (#3599) carry back
    /// to the extension.
    public var recordIdentifier: String { "\(accountKey)/\(itemId)" }
}

/// What the AutoFill extension does with a cache and the key the Keychain gave it (#3598): which entries a
/// site gets, and the one password the user picked. Every step fails closed
/// (docs/design/native-autofill-vault.md, "Failure UX").
public enum VaultAutofill {
    /// Whether `vaultKey` is the key `fingerprint` was taken of, the fingerprint the app stored beside it. A key
    /// that disagrees fills nothing.
    public static func keyMatches(_ vaultKey: [UInt8], fingerprint: [UInt8], crypto: VaultCrypto = VaultCrypto()) -> Bool {
        guard let actual = crypto.fingerprint(vaultKey: vaultKey) else { return false }
        return actual == fingerprint
    }

    /// The cache's entries for the sites in `serviceIdentifiers` (a domain or a URL each, as iOS hands them),
    /// matched as `VaultController.entriesForUrl` matches, or every entry when there are none. Nil when the key
    /// is not this vault's: items at the format this code reads exist and none of them opens.
    public static func entries(
        in cache: VaultAutofillCache,
        matching serviceIdentifiers: [String],
        vaultKey: [UInt8],
        crypto: VaultCrypto = VaultCrypto()
    ) -> [VaultAutofillEntry]? {
        var readable = 0
        var opened = 0
        var entries: [VaultAutofillEntry] = []
        for item in cache.items where item.formatVersion == VaultCrypto.formatVersion {
            readable += 1
            guard let plaintext = crypto.openItem(
                ciphertext: item.ciphertext, nonce: item.nonce, formatVersion: item.formatVersion, vaultKey: vaultKey
            ) else { continue }
            opened += 1
            guard let data = VaultItemData.decode(plaintext), data.kind == .entry else { continue }
            if !serviceIdentifiers.isEmpty,
               !serviceIdentifiers.contains(where: { VaultHosts.matches(url: $0, site: data.url) }) {
                continue
            }
            entries.append(VaultAutofillEntry(
                accountKey: cache.accountKey, itemId: item.id, name: data.name, username: data.username, site: data.urlHost
            ))
        }
        if readable > 0 && opened == 0 { return nil }
        return entries
    }

    /// The username and password of `entry`, opened again from the cache. Nil when it is gone, no longer opens,
    /// or has no password: nothing is filled then.
    public static func credential(
        for entry: VaultAutofillEntry,
        in cache: VaultAutofillCache,
        vaultKey: [UInt8],
        crypto: VaultCrypto = VaultCrypto()
    ) -> (username: String, password: String)? {
        guard cache.accountKey == entry.accountKey,
              let item = cache.items.first(where: { $0.id == entry.itemId }),
              let plaintext = crypto.openItem(
                ciphertext: item.ciphertext, nonce: item.nonce, formatVersion: item.formatVersion, vaultKey: vaultKey
              ),
              let data = VaultItemData.decode(plaintext),
              data.kind == .entry, !data.password.isEmpty
        else { return nil }
        return (data.username, data.password)
    }
}
