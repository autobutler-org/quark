// cspell:words vaultkeystore
package org.autobutler.vaultkeystore

/**
 * The file an account's cached vault key lives in on Android (#3595, docs/design/native-autofill-vault.md,
 * "Android: a Keystore key that needs authentication for every use"):
 *
 * ```text
 * version (1 byte, 1) || fingerprint (16 bytes) || GCM IV (12 bytes) || AES-256-GCM(vaultKey) with its tag
 * ```
 *
 * The AES key is `quark_vault_autofill_v1` in `AndroidKeyStore`, and the additional data is the account key,
 * so a file renamed to another account does not open. The fingerprint sits in the clear, because it says
 * nothing about the key without the key, so the app can read whether biometric unlock is on without a
 * prompt. Plain JVM code, so the JVM unit tests cover it.
 */
object VaultKeyFile {
    const val VERSION: Byte = 1
    const val FINGERPRINT_BYTES = 16
    const val IV_BYTES = 12
    const val VAULT_KEY_BYTES = 32
    private const val TAG_BYTES = 16
    private const val HEADER_BYTES = 1 + FINGERPRINT_BYTES + IV_BYTES
    private val ACCOUNT_KEY = Regex("^acct_[0-9a-f]{32}$")

    /** One parsed file. */
    class Parsed(val fingerprint: ByteArray, val iv: ByteArray, val sealed: ByteArray)

    /**
     * Whether [account] is an account key as `VaultCache.accountKey` makes it. It names a file, so anything
     * else, a path separator above all, is refused.
     */
    fun isAccountKey(account: String?): Boolean = account != null && ACCOUNT_KEY.matches(account)

    /** The file's name for [account]. */
    fun fileName(account: String): String {
        require(isAccountKey(account)) { "not an account key" }
        return "$account.bin"
    }

    /** The file's bytes. */
    fun encode(fingerprint: ByteArray, iv: ByteArray, sealed: ByteArray): ByteArray {
        require(fingerprint.size == FINGERPRINT_BYTES) { "a fingerprint is $FINGERPRINT_BYTES bytes" }
        require(iv.size == IV_BYTES) { "a GCM IV is $IV_BYTES bytes" }
        require(sealed.size == VAULT_KEY_BYTES + TAG_BYTES) { "a sealed vault key is ${VAULT_KEY_BYTES + TAG_BYTES} bytes" }
        return byteArrayOf(VERSION) + fingerprint + iv + sealed
    }

    /** What [encode] wrote, or null for a file of another version or length. */
    fun decode(bytes: ByteArray): Parsed? {
        if (bytes.size != HEADER_BYTES + VAULT_KEY_BYTES + TAG_BYTES || bytes[0] != VERSION) return null
        return Parsed(
            fingerprint = bytes.copyOfRange(1, 1 + FINGERPRINT_BYTES),
            iv = bytes.copyOfRange(1 + FINGERPRINT_BYTES, HEADER_BYTES),
            sealed = bytes.copyOfRange(HEADER_BYTES, bytes.size),
        )
    }
}
