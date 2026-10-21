// cspell:words lazysodium goterl generichash
package org.autobutler.vaultcrypto

import com.goterl.lazysodium.LazySodium

/**
 * The vault's crypto as `lib/services/account_crypto.dart` does it (#3597), for the autofill service, which
 * runs with no Flutter engine. It opens the vault key's wrap and the items, seals an item, and fingerprints a
 * key. It never derives a key: the service never sees the password (docs/design/native-autofill-vault.md,
 * Decision 1).
 *
 * Every opening fails closed, returning null for a wrong key, a tampered or truncated input, a bad nonce or a
 * format version this code does not read. `test/fixtures/vault_vectors.json` pins it to the Dart.
 *
 * [sodium] is `LazySodiumAndroid(SodiumAndroid())` in the app, and `LazySodiumJava(SodiumJava())` in the JVM
 * tests.
 */
class VaultCrypto(private val sodium: LazySodium) {
    /**
     * Opens `nonce || XChaCha20-Poly1305(vaultKey)`, the vault key's wrap under [wrapKey]
     * (`AccountCrypto.unwrapVaultKey`). Null when it does not open.
     */
    fun unwrapVaultKey(wrapped: ByteArray, wrapKey: ByteArray): ByteArray? {
        if (wrapped.size <= NONCE_BYTES) return null
        return open(
            wrapped.copyOfRange(NONCE_BYTES, wrapped.size),
            wrapped.copyOfRange(0, NONCE_BYTES),
            wrapKey,
            null,
        )
    }

    /**
     * Opens one vault item (`AccountCrypto.decryptVaultItem`): XChaCha20-Poly1305 with the additional data
     * `utf8("quark-vault-item-v1") || 0x00 || formatVersion`. A [formatVersion] other than
     * [FORMAT_VERSION] is skipped as the app skips it, so null. The result is the item's UTF-8 JSON, which
     * [VaultItemData.decode] reads.
     */
    fun openItem(ciphertext: ByteArray, nonce: ByteArray, formatVersion: Int, vaultKey: ByteArray): ByteArray? {
        if (formatVersion != FORMAT_VERSION || nonce.size != NONCE_BYTES) return null
        return open(ciphertext, nonce, vaultKey, itemAd(formatVersion))
    }

    /**
     * Seals [plaintext] as an item at [FORMAT_VERSION] (`AccountCrypto.encryptVaultItem`), under a fresh
     * random nonce unless the caller passes one.
     */
    fun sealItem(
        plaintext: ByteArray,
        vaultKey: ByteArray,
        nonce: ByteArray = sodium.randomBytesBuf(NONCE_BYTES),
    ): SealedItem {
        require(vaultKey.size == KEY_BYTES) { "a vault key is $KEY_BYTES bytes" }
        require(nonce.size == NONCE_BYTES) { "a nonce is $NONCE_BYTES bytes" }
        val ad = itemAd(FORMAT_VERSION)
        val ciphertext = ByteArray(plaintext.size + TAG_BYTES)
        check(
            sodium.cryptoAeadXChaCha20Poly1305IetfEncrypt(
                ciphertext, null, plaintext, plaintext.size.toLong(), ad, ad.size.toLong(), null, nonce, vaultKey,
            ),
        ) { "libsodium refused to seal" }
        return SealedItem(ciphertext, nonce, FORMAT_VERSION)
    }

    /**
     * The key's fingerprint, `crypto_generichash(16, "quark-vault-key-fingerprint-v1", key = vaultKey)`: keyed
     * BLAKE2b, which says nothing about the key without it (docs/design/native-autofill-vault.md, "Detecting
     * a stale cached key").
     */
    fun fingerprint(vaultKey: ByteArray): ByteArray {
        require(vaultKey.size == KEY_BYTES) { "a vault key is $KEY_BYTES bytes" }
        val out = ByteArray(FINGERPRINT_BYTES)
        val message = FINGERPRINT_MESSAGE.toByteArray(Charsets.UTF_8)
        check(
            sodium.cryptoGenericHash(out, out.size, message, message.size.toLong(), vaultKey, vaultKey.size),
        ) { "libsodium refused to hash" }
        return out
    }

    private fun open(ciphertext: ByteArray, nonce: ByteArray, key: ByteArray, ad: ByteArray?): ByteArray? {
        if (key.size != KEY_BYTES || ciphertext.size < TAG_BYTES) return null
        val message = ByteArray(ciphertext.size - TAG_BYTES)
        val opened = sodium.cryptoAeadXChaCha20Poly1305IetfDecrypt(
            message, null, null, ciphertext, ciphertext.size.toLong(), ad, (ad?.size ?: 0).toLong(), nonce, key,
        )
        return if (opened) message else null
    }

    private fun itemAd(formatVersion: Int): ByteArray =
        ITEM_AD_PREFIX.toByteArray(Charsets.UTF_8) + byteArrayOf(0, formatVersion.toByte())

    companion object {
        /** The plaintext layout this code reads and writes, `VaultItemData.formatVersion`. */
        const val FORMAT_VERSION = 1

        /** A vault key's length, and a wrap key's. */
        const val KEY_BYTES = 32

        /** An XChaCha20-Poly1305 nonce's length. */
        const val NONCE_BYTES = 24

        private const val TAG_BYTES = 16
        private const val FINGERPRINT_BYTES = 16
        private const val ITEM_AD_PREFIX = "quark-vault-item-v1"
        private const val FINGERPRINT_MESSAGE = "quark-vault-key-fingerprint-v1"
    }
}

/** One sealed item as the Quark stores it: ciphertext, nonce and the plaintext layout's version. */
class SealedItem(val ciphertext: ByteArray, val nonce: ByteArray, val formatVersion: Int)
