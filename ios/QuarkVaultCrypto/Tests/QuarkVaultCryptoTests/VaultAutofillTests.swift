import Foundation
import XCTest

@testable import QuarkVaultCrypto

/// The AutoFill extension's reading of the ciphertext cache (#3598): the file `lib/services/vault_cache.dart`
/// writes, which entries a site gets, and that every doubt fills nothing. The item is the one
/// `test/fixtures/vault_vectors.json` pins, a GitHub login for `https://github.com/login`.
final class VaultAutofillTests: XCTestCase {
    private let account = "acct_0123456789abcdef0123456789abcdef"
    private var item: [String: Any] = [:]
    private var key: [UInt8] = []
    private var fingerprints: [[String: Any]] = []

    override func setUpWithError() throws {
        // This file is in ios/QuarkVaultCrypto/Tests/QuarkVaultCryptoTests/, four directories below the repository.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("test/fixtures/vault_vectors.json"))
        let vectors = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        item = try XCTUnwrap(vectors["item"] as? [String: Any])
        key = try XCTUnwrap(item["key"] as? [Int]).map { UInt8($0) }
        fingerprints = try XCTUnwrap(vectors["fingerprints"] as? [[String: Any]])
    }

    /// A cache file shaped as `VaultCache.encode` writes it, with Dart's microsecond timestamp.
    private func file(schema: Int = 1, items: [[String: Any]]? = nil) throws -> Data {
        let items = try items ?? [[
            "id": 42,
            "ciphertext": try XCTUnwrap(item["ciphertext"] as? String),
            "nonce": try XCTUnwrap(item["nonce"] as? String),
            "formatVersion": 1,
        ]]
        return try JSONSerialization.data(withJSONObject: [
            "schema": schema,
            "host": "https://quark.local",
            "username": "you",
            "syncedAt": "2026-10-20T12:00:00.123456Z",
            "items": items,
        ])
    }

    private func cache() throws -> VaultAutofillCache {
        try XCTUnwrap(VaultAutofillCache.decode(try file(), accountKey: account))
    }

    func testItReadsTheFileTheAppWrites() throws {
        let cache = try cache()
        XCTAssertEqual(cache.accountKey, account)
        XCTAssertEqual(cache.host, "https://quark.local")
        XCTAssertEqual(cache.username, "you")
        XCTAssertEqual(cache.items.map(\.id), [42])
        XCTAssertEqual(cache.syncedAt, ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z"))
    }

    func testItRefusesAFileItDoesNotUnderstand() throws {
        XCTAssertNil(VaultAutofillCache.decode(try file(schema: 2), accountKey: account), "a newer schema")
        XCTAssertNil(VaultAutofillCache.decode(try file(), accountKey: "acct_../escape"), "a bad account key")
        XCTAssertNil(
            VaultAutofillCache.decode(try file(items: [["id": 1, "ciphertext": "%%", "nonce": "", "formatVersion": 1]]), accountKey: account),
            "an item that is not base64"
        )
        XCTAssertNil(VaultAutofillCache.decode(Data("not json".utf8), accountKey: account), "not JSON")
    }

    func testItLoadsEveryAccountFileInTheDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try file().write(to: dir.appendingPathComponent("\(account).json"))
        try file().write(to: dir.appendingPathComponent("\(account).json.tmp"))
        try Data("{}".utf8).write(to: dir.appendingPathComponent("acct_ffffffffffffffffffffffffffffffff.json"))

        XCTAssertEqual(VaultAutofillCache.load(directory: dir).map(\.accountKey), [account])
        XCTAssertEqual(VaultAutofillCache.load(directory: dir.appendingPathComponent("missing")), [])
    }

    func testASiteGetsItsEntriesAndAParentDomainMatches() throws {
        let cache = try cache()
        let expected = [VaultAutofillEntry(accountKey: account, itemId: 42, name: "GitHub", username: "octocat", site: "github.com")]
        XCTAssertEqual(VaultAutofill.entries(in: cache, matching: ["github.com"], vaultKey: key), expected)
        XCTAssertEqual(VaultAutofill.entries(in: cache, matching: ["https://gist.github.com/new"], vaultKey: key), expected)
        XCTAssertEqual(VaultAutofill.entries(in: cache, matching: [], vaultKey: key), expected, "no site lists every entry")
        XCTAssertEqual(VaultAutofill.entries(in: cache, matching: ["badgithub.com"], vaultKey: key), [], "a lookalike")
        XCTAssertEqual(expected[0].recordIdentifier, "\(account)/42")
    }

    func testAKeyThatOpensNothingFillsNothing() throws {
        let wrong = [UInt8](repeating: 7, count: 32)
        XCTAssertNil(VaultAutofill.entries(in: try cache(), matching: ["github.com"], vaultKey: wrong))
        let empty = VaultAutofillCache(accountKey: account, host: "", username: "", syncedAt: nil, items: [])
        XCTAssertEqual(VaultAutofill.entries(in: empty, matching: [], vaultKey: wrong), [], "an empty vault is not stale")
    }

    func testOnlyThePickedEntryOpensToItsPassword() throws {
        let cache = try cache()
        let entry = try XCTUnwrap(VaultAutofill.entries(in: cache, matching: ["github.com"], vaultKey: key)?.first)
        let credential = try XCTUnwrap(VaultAutofill.credential(for: entry, in: cache, vaultKey: key))
        XCTAssertEqual(credential.username, "octocat")
        XCTAssertEqual(credential.password, "hunter2")

        let gone = VaultAutofillEntry(accountKey: account, itemId: 9, name: "", username: "", site: "")
        XCTAssertNil(VaultAutofill.credential(for: gone, in: cache, vaultKey: key))
        XCTAssertNil(VaultAutofill.credential(for: entry, in: cache, vaultKey: [UInt8](repeating: 7, count: 32)))
    }

    func testAQuickTypeRecordIsHeldOnlyWhileTheCacheListsItsItem() throws {
        let cache = try cache()
        let entry = try XCTUnwrap(VaultAutofill.entries(in: cache, matching: [], vaultKey: key)?.first)
        XCTAssertTrue(cache.holds(recordIdentifier: entry.recordIdentifier))
        XCTAssertFalse(cache.holds(recordIdentifier: "\(account)/9"), "an item since deleted")
        XCTAssertFalse(cache.holds(recordIdentifier: "acct_ffffffffffffffffffffffffffffffff/42"), "another account")
        XCTAssertFalse(cache.holds(recordIdentifier: "\(account)/42/1"), "a record that does not parse")
        XCTAssertFalse(cache.holds(recordIdentifier: account), "no item id")
    }

    func testTheKeyMustMatchTheStoredFingerprint() throws {
        for vector in fingerprints {
            let vectorKey = try XCTUnwrap(vector["key"] as? [Int]).map { UInt8($0) }
            let fingerprint = Array(try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(vector["fingerprint"] as? String))))
            XCTAssertTrue(VaultAutofill.keyMatches(vectorKey, fingerprint: fingerprint))
            XCTAssertFalse(VaultAutofill.keyMatches(key == vectorKey ? [UInt8](repeating: 7, count: 32) : key, fingerprint: fingerprint))
        }
    }
}
