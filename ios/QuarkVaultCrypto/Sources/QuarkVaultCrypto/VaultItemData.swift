// cspell:words totp
import Foundation

/// Entry or folder, as `VaultItemKind` names them in the item JSON.
public enum VaultItemKind: String, Equatable {
    /// A saved login.
    case entry

    /// A folder entries are filed in.
    case folder
}

/// A name and value the user added to an entry, `VaultCustomField`.
public struct VaultCustomField: Equatable {
    public let label: String
    public let value: String
    public let hidden: Bool

    public init(label: String, value: String, hidden: Bool) {
        self.label = label
        self.value = value
        self.hidden = hidden
    }
}

/// One decrypted vault item, read as `VaultItemData.fromJson` (`lib/models/vault_item.dart`) reads it (#3597):
/// a missing or null field is empty, an unknown key is ignored, and an unknown `kind` or a field of the wrong
/// type is refused, since guessing would lose what a newer app wrote. The `itemJson` cases in
/// `test/fixtures/vault_vectors.json` pin it.
public struct VaultItemData: Equatable {
    public let kind: VaultItemKind
    public let name: String
    public let url: String
    public let username: String
    public let password: String
    public let notes: String
    public let totpSecret: String
    public let customFields: [VaultCustomField]
    public let folderId: Int64?

    public init(
        kind: VaultItemKind,
        name: String,
        url: String,
        username: String,
        password: String,
        notes: String,
        totpSecret: String,
        customFields: [VaultCustomField],
        folderId: Int64?
    ) {
        self.kind = kind
        self.name = name
        self.url = url
        self.username = username
        self.password = password
        self.notes = notes
        self.totpSecret = totpSecret
        self.customFields = customFields
        self.folderId = folderId
    }

    /// `url`'s host as ``VaultHosts/hostOf(_:)`` reads it.
    public var urlHost: String { VaultHosts.hostOf(url) }

    /// Reads an item's UTF-8 JSON, what ``VaultCrypto/openItem(ciphertext:nonce:formatVersion:vaultKey:)``
    /// returns. Nil when the app would refuse it.
    public static func decode(_ plaintext: [UInt8]) -> VaultItemData? {
        guard case let .object(json)? = try? JSONDecoder().decode(JSONValue.self, from: Data(plaintext)) else {
            return nil
        }
        return try? fromJson(json)
    }

    private static func fromJson(_ json: [String: JSONValue]) throws -> VaultItemData? {
        guard let kind = VaultItemKind(rawValue: try json.string("kind") ?? VaultItemKind.entry.rawValue) else {
            return nil
        }
        var customFields: [VaultCustomField] = []
        switch json["customFields"] {
        case nil, .null?:
            break
        case let .array(fields)?:
            for field in fields {
                guard case let .object(field) = field else { throw JSONValue.WrongType() }
                customFields.append(VaultCustomField(
                    label: try field.string("label") ?? "",
                    value: try field.string("value") ?? "",
                    hidden: try field.bool("hidden") ?? false
                ))
            }
        default:
            throw JSONValue.WrongType()
        }
        return VaultItemData(
            kind: kind,
            name: try json.string("name") ?? "",
            url: try json.string("url") ?? "",
            username: try json.string("username") ?? "",
            password: try json.string("password") ?? "",
            notes: try json.string("notes") ?? "",
            totpSecret: try json.string("totpSecret") ?? "",
            customFields: customFields,
            folderId: try json.int("folderId")
        )
    }
}

/// A decoded JSON value that keeps a boolean apart from a number, as Dart's `jsonDecode` does.
/// `JSONSerialization` hands both back as `NSNumber`, so it cannot tell `"hidden": 1` from `true`.
enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    struct WrongType: Error {}

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int64.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    /// The string at `key`, nil when it is missing or null; a value of another type throws.
    func string(_ key: String) throws -> String? {
        switch self[key] {
        case nil, .null?: return nil
        case let .string(s)?: return s
        default: throw JSONValue.WrongType()
        }
    }

    func bool(_ key: String) throws -> Bool? {
        switch self[key] {
        case nil, .null?: return nil
        case let .bool(b)?: return b
        default: throw JSONValue.WrongType()
        }
    }

    /// A number read as Dart's `(json[key] as num?)?.toInt()` reads it, truncating toward zero.
    func int(_ key: String) throws -> Int64? {
        switch self[key] {
        case nil, .null?: return nil
        case let .int(i)?: return i
        case let .double(d)?:
            guard let i = Int64(exactly: d.rounded(.towardZero)) else { throw JSONValue.WrongType() }
            return i
        default: throw JSONValue.WrongType()
        }
    }
}
