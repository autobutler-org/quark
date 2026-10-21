import Sodium

/// The vault's crypto as `lib/services/account_crypto.dart` does it (#3597), for the AutoFill extension, which
/// runs with no Flutter engine. It opens the vault key's wrap and the items, and fingerprints a key. It never
/// derives a key, since the extension never sees the password, and it never seals: only Android saves
/// (docs/design/native-autofill-vault.md, Decision 1).
///
/// Every opening fails closed, returning nil for a wrong key, a tampered or truncated input, a bad nonce or a
/// format version this code does not read. `test/fixtures/vault_vectors.json` pins it to the Dart.
public struct VaultCrypto {
    /// The plaintext layout this code reads, `VaultItemData.formatVersion`.
    public static let formatVersion = 1

    /// A vault key's length, and a wrap key's.
    public static let keyBytes = 32

    /// An XChaCha20-Poly1305 nonce's length.
    public static let nonceBytes = 24

    private static let tagBytes = 16
    private static let fingerprintBytes = 16
    private static let itemAdPrefix = Array("quark-vault-item-v1".utf8)
    private static let fingerprintMessage = Array("quark-vault-key-fingerprint-v1".utf8)

    private let sodium = Sodium()

    /// Loads libsodium.
    public init() {}

    /// Opens `nonce || XChaCha20-Poly1305(vaultKey)`, the vault key's wrap under `wrapKey`
    /// (`AccountCrypto.unwrapVaultKey`). Nil when it does not open.
    public func unwrapVaultKey(_ wrapped: [UInt8], wrapKey: [UInt8]) -> [UInt8]? {
        guard wrapped.count > Self.nonceBytes else { return nil }
        return open(
            Array(wrapped[Self.nonceBytes...]),
            nonce: Array(wrapped[..<Self.nonceBytes]),
            key: wrapKey,
            additionalData: nil
        )
    }

    /// Opens one vault item (`AccountCrypto.decryptVaultItem`): XChaCha20-Poly1305 with the additional data
    /// `utf8("quark-vault-item-v1") || 0x00 || formatVersion`. A `formatVersion` other than
    /// ``formatVersion`` is skipped as the app skips it, so nil. The result is the item's UTF-8 JSON, which
    /// ``VaultItemData/decode(_:)`` reads.
    public func openItem(
        ciphertext: [UInt8],
        nonce: [UInt8],
        formatVersion: Int,
        vaultKey: [UInt8]
    ) -> [UInt8]? {
        guard formatVersion == Self.formatVersion else { return nil }
        return open(
            ciphertext,
            nonce: nonce,
            key: vaultKey,
            additionalData: Self.itemAdPrefix + [0, UInt8(formatVersion)]
        )
    }

    /// The key's fingerprint, `crypto_generichash(16, "quark-vault-key-fingerprint-v1", key = vaultKey)`:
    /// keyed BLAKE2b, which says nothing about the key without it (docs/design/native-autofill-vault.md,
    /// "Detecting a stale cached key"). Nil for a key of the wrong length.
    public func fingerprint(vaultKey: [UInt8]) -> [UInt8]? {
        guard vaultKey.count == Self.keyBytes else { return nil }
        return sodium.genericHash.hash(
            message: Self.fingerprintMessage,
            key: vaultKey,
            outputLength: Self.fingerprintBytes
        )
    }

    /// libsodium reads a fixed length from the key and the nonce, so both are checked here before it does.
    private func open(
        _ ciphertext: [UInt8],
        nonce: [UInt8],
        key: [UInt8],
        additionalData: [UInt8]?
    ) -> [UInt8]? {
        guard key.count == Self.keyBytes,
              nonce.count == Self.nonceBytes,
              ciphertext.count >= Self.tagBytes
        else { return nil }
        return sodium.aead.xchacha20poly1305ietf.decrypt(
            authenticatedCipherText: ciphertext,
            secretKey: key,
            nonce: nonce,
            additionalData: additionalData
        )
    }
}
