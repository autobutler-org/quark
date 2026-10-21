// cspell:words totp
import Foundation
import XCTest

@testable import QuarkVaultCrypto

/// Pins the Swift vault code to the Dart (#3597) through `test/fixtures/vault_vectors.json`, which
/// `test/services/vault_vectors_test.dart` generates from the Dart and checks for drift.
final class VaultVectorsTests: XCTestCase {
    private let crypto = VaultCrypto()
    private var vectors: [String: Any] = [:]

    override func setUpWithError() throws {
        // This file is in ios/QuarkVaultCrypto/Tests/QuarkVaultCryptoTests/, four directories below the repository.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("test/fixtures/vault_vectors.json"))
        vectors = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheWrapOpensToTheVaultKey() throws {
        let wrap = try object("wrap")
        XCTAssertEqual(
            crypto.unwrapVaultKey(try b64(wrap["wrapped"]), wrapKey: try bytes(wrap["vaultWrapKey"])),
            try bytes(wrap["vaultKey"])
        )
    }

    func testEveryWrapRejectionFailsClosed() throws {
        for rejection in try list(try object("wrap")["rejections"]) {
            XCTAssertNil(
                crypto.unwrapVaultKey(try b64(rejection["wrapped"]), wrapKey: try bytes(rejection["key"])),
                "\(rejection["name"] ?? "")"
            )
        }
    }

    func testTheItemOpensToItsPlaintext() throws {
        let item = try object("item")
        let opened = try XCTUnwrap(crypto.openItem(
            ciphertext: try b64(item["ciphertext"]),
            nonce: try b64(item["nonce"]),
            formatVersion: try XCTUnwrap(item["formatVersion"] as? Int),
            vaultKey: try bytes(item["key"])
        ))
        XCTAssertEqual(String(decoding: opened, as: UTF8.self), item["plaintext"] as? String)
        XCTAssertEqual(VaultItemData.decode(opened)?.name, "GitHub")
    }

    func testEveryItemRejectionFailsClosed() throws {
        for rejection in try list(try object("item")["rejections"]) {
            XCTAssertNil(
                crypto.openItem(
                    ciphertext: try b64(rejection["ciphertext"]),
                    nonce: try b64(rejection["nonce"]),
                    formatVersion: try XCTUnwrap(rejection["formatVersion"] as? Int),
                    vaultKey: try bytes(rejection["key"])
                ),
                "\(rejection["name"] ?? "")"
            )
        }
    }

    func testFingerprintsMatch() throws {
        for vector in try list(vectors["fingerprints"]) {
            XCTAssertEqual(crypto.fingerprint(vaultKey: try bytes(vector["key"])), try b64(vector["fingerprint"]))
        }
    }

    func testHostsAreReadAsDartReadsThem() throws {
        for vector in try list(vectors["hosts"]) {
            let url = try XCTUnwrap(vector["url"] as? String)
            XCTAssertEqual(VaultHosts.hostOf(url), vector["host"] as? String, url)
        }
    }

    func testSitesMatchAsEntriesForUrlMatchesThem() throws {
        for vector in try list(vectors["matches"]) {
            let url = try XCTUnwrap(vector["url"] as? String)
            let site = try XCTUnwrap(vector["site"] as? String)
            XCTAssertEqual(
                VaultHosts.matches(url: url, site: site),
                try XCTUnwrap(vector["matches"] as? Bool),
                "\(url) against \(site)"
            )
        }
    }

    func testItemJsonReadsAsFromJsonReadsIt() throws {
        for vector in try list(vectors["itemJson"]) {
            let name = try XCTUnwrap(vector["name"] as? String)
            let json = try XCTUnwrap(vector["json"] as? String)
            let item = VaultItemData.decode(Array(json.utf8))
            if vector["error"] as? Bool == true {
                XCTAssertNil(item, name)
                continue
            }
            let want = try XCTUnwrap(vector["item"] as? [String: Any])
            XCTAssertEqual(
                item,
                VaultItemData(
                    kind: try XCTUnwrap(VaultItemKind(rawValue: try XCTUnwrap(want["kind"] as? String))),
                    name: try XCTUnwrap(want["name"] as? String),
                    url: try XCTUnwrap(want["url"] as? String),
                    username: try XCTUnwrap(want["username"] as? String),
                    password: try XCTUnwrap(want["password"] as? String),
                    notes: try XCTUnwrap(want["notes"] as? String),
                    totpSecret: try XCTUnwrap(want["totpSecret"] as? String),
                    customFields: try list(want["customFields"]).map {
                        VaultCustomField(
                            label: try XCTUnwrap($0["label"] as? String),
                            value: try XCTUnwrap($0["value"] as? String),
                            hidden: try XCTUnwrap($0["hidden"] as? Bool)
                        )
                    },
                    folderId: (want["folderId"] as? NSNumber)?.int64Value
                ),
                name
            )
        }
    }

    private func object(_ key: String) throws -> [String: Any] {
        try XCTUnwrap(vectors[key] as? [String: Any], key)
    }

    private func list(_ value: Any?) throws -> [[String: Any]] {
        try XCTUnwrap(value as? [[String: Any]])
    }

    /// Keys are byte arrays in the file, so secret scanners do not read them as leaked credentials.
    private func bytes(_ value: Any?) throws -> [UInt8] {
        try XCTUnwrap(value as? [Int]).map { UInt8($0) }
    }

    private func b64(_ value: Any?) throws -> [UInt8] {
        let text = try XCTUnwrap(value as? String)
        return Array(try XCTUnwrap(Data(base64Encoded: text), text))
    }
}
