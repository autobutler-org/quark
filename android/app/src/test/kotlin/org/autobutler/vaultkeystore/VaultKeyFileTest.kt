// cspell:words vaultkeystore
package org.autobutler.vaultkeystore

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The cached vault key's file (#3595): its layout, and the account keys that may name one. */
class VaultKeyFileTest {
    private val fingerprint = ByteArray(16) { it.toByte() }
    private val iv = ByteArray(12) { (it + 100).toByte() }
    private val sealed = ByteArray(48) { (it + 7).toByte() }

    @Test
    fun roundTrips() {
        val parsed = VaultKeyFile.decode(VaultKeyFile.encode(fingerprint, iv, sealed))!!
        assertArrayEquals(fingerprint, parsed.fingerprint)
        assertArrayEquals(iv, parsed.iv)
        assertArrayEquals(sealed, parsed.sealed)
    }

    @Test
    fun startsWithItsVersionAndTheFingerprintInTheClear() {
        val bytes = VaultKeyFile.encode(fingerprint, iv, sealed)
        assertTrue(bytes[0] == VaultKeyFile.VERSION)
        assertArrayEquals(fingerprint, bytes.copyOfRange(1, 17))
    }

    @Test
    fun refusesAnotherVersionOrLength() {
        val bytes = VaultKeyFile.encode(fingerprint, iv, sealed)
        assertNull(VaultKeyFile.decode(bytes.copyOf().also { it[0] = 2 }))
        assertNull(VaultKeyFile.decode(bytes.copyOf(bytes.size - 1)))
        assertNull(VaultKeyFile.decode(bytes + 0))
        assertNull(VaultKeyFile.decode(ByteArray(0)))
    }

    @Test(expected = IllegalArgumentException::class)
    fun refusesAShortFingerprint() {
        VaultKeyFile.encode(ByteArray(15), iv, sealed)
    }

    @Test(expected = IllegalArgumentException::class)
    fun refusesASealedKeyOfTheWrongLength() {
        VaultKeyFile.encode(fingerprint, iv, ByteArray(32))
    }

    @Test
    fun acceptsOnlyAccountKeys() {
        assertTrue(VaultKeyFile.isAccountKey("acct_0123456789abcdef0123456789abcdef"))
        assertFalse(VaultKeyFile.isAccountKey(null))
        assertFalse(VaultKeyFile.isAccountKey("acct_0123456789ABCDEF0123456789abcdef"))
        assertFalse(VaultKeyFile.isAccountKey("acct_0123456789abcdef"))
        assertFalse(VaultKeyFile.isAccountKey("../acct_0123456789abcdef0123456789abcdef"))
        assertFalse(VaultKeyFile.isAccountKey("acct_0123456789abcdef0123456789abcdef/.."))
    }

    @Test(expected = IllegalArgumentException::class)
    fun namesNoFileForAPath() {
        VaultKeyFile.fileName("../../shared_prefs/x")
    }
}
