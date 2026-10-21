// cspell:words lazysodium goterl totp
package org.autobutler.vaultcrypto

import com.goterl.lazysodium.LazySodiumJava
import com.goterl.lazysodium.SodiumJava
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File
import java.util.Base64

/**
 * Pins the Kotlin vault code to the Dart (#3597) through `test/fixtures/vault_vectors.json`, which
 * `test/services/vault_vectors_test.dart` generates from the Dart and checks for drift. Runs on the JVM with
 * lazysodium-java's bundled libsodium, the same C library the app links on Android.
 */
class VaultVectorsTest {
    private val crypto = VaultCrypto(LazySodiumJava(SodiumJava()))

    // Gradle runs unit tests in the module directory, android/app.
    private val vectors = JSONObject(File("../../test/fixtures/vault_vectors.json").readText())

    @Test
    fun `the wrap opens to the vault key`() {
        val wrap = vectors.getJSONObject("wrap")
        assertArrayEquals(
            bytes(wrap.getJSONArray("vaultKey")),
            crypto.unwrapVaultKey(b64(wrap.getString("wrapped")), bytes(wrap.getJSONArray("vaultWrapKey"))),
        )
    }

    @Test
    fun `every wrap rejection fails closed`() {
        for (case in vectors.getJSONObject("wrap").getJSONArray("rejections").objects()) {
            assertNull(
                case.getString("name"),
                crypto.unwrapVaultKey(b64(case.getString("wrapped")), bytes(case.getJSONArray("key"))),
            )
        }
    }

    @Test
    fun `the item opens to its plaintext`() {
        val item = vectors.getJSONObject("item")
        val opened = crypto.openItem(
            b64(item.getString("ciphertext")),
            b64(item.getString("nonce")),
            item.getInt("formatVersion"),
            bytes(item.getJSONArray("key")),
        )
        assertEquals(item.getString("plaintext"), opened?.toString(Charsets.UTF_8))
        assertEquals("GitHub", VaultItemData.decode(opened!!)?.name)
    }

    @Test
    fun `sealing under the item's nonce gives its exact bytes, and a fresh seal opens`() {
        val item = vectors.getJSONObject("item")
        val key = bytes(item.getJSONArray("key"))
        val plaintext = item.getString("plaintext").toByteArray(Charsets.UTF_8)

        val sealed = crypto.sealItem(plaintext, key, b64(item.getString("nonce")))
        assertArrayEquals(b64(item.getString("ciphertext")), sealed.ciphertext)
        assertEquals(item.getInt("formatVersion"), sealed.formatVersion)

        val fresh = crypto.sealItem(plaintext, key)
        assertFalse(fresh.nonce.contentEquals(sealed.nonce))
        assertArrayEquals(plaintext, crypto.openItem(fresh.ciphertext, fresh.nonce, fresh.formatVersion, key))
    }

    @Test
    fun `every item rejection fails closed`() {
        for (case in vectors.getJSONObject("item").getJSONArray("rejections").objects()) {
            assertNull(
                case.getString("name"),
                crypto.openItem(
                    b64(case.getString("ciphertext")),
                    b64(case.getString("nonce")),
                    case.getInt("formatVersion"),
                    bytes(case.getJSONArray("key")),
                ),
            )
        }
    }

    @Test
    fun `fingerprints match`() {
        for (case in vectors.getJSONArray("fingerprints").objects()) {
            assertArrayEquals(b64(case.getString("fingerprint")), crypto.fingerprint(bytes(case.getJSONArray("key"))))
        }
    }

    @Test
    fun `hosts are read as Dart reads them`() {
        for (case in vectors.getJSONArray("hosts").objects()) {
            assertEquals(case.getString("url"), case.getString("host"), VaultHosts.hostOf(case.getString("url")))
        }
    }

    @Test
    fun `sites match as entriesForUrl matches them`() {
        for (case in vectors.getJSONArray("matches").objects()) {
            val url = case.getString("url")
            val site = case.getString("site")
            assertEquals("$url against $site", case.getBoolean("matches"), VaultHosts.matches(url, site))
        }
    }

    @Test
    fun `item JSON reads as fromJson reads it`() {
        for (case in vectors.getJSONArray("itemJson").objects()) {
            val name = case.getString("name")
            val item = VaultItemData.decode(case.getString("json").toByteArray(Charsets.UTF_8))
            if (case.optBoolean("error")) {
                assertNull(name, item)
                continue
            }
            assertNotNull(name, item)
            val want = case.getJSONObject("item")
            assertEquals(
                name,
                VaultItemData(
                    kind = VaultItemKind.entries.single { it.jsonName == want.getString("kind") },
                    name = want.getString("name"),
                    url = want.getString("url"),
                    username = want.getString("username"),
                    password = want.getString("password"),
                    notes = want.getString("notes"),
                    totpSecret = want.getString("totpSecret"),
                    customFields = want.getJSONArray("customFields").objects().map {
                        VaultCustomField(it.getString("label"), it.getString("value"), it.getBoolean("hidden"))
                    },
                    folderId = if (want.isNull("folderId")) null else want.getLong("folderId"),
                ),
                item,
            )
        }
    }

    private fun b64(text: String): ByteArray = Base64.getDecoder().decode(text)

    /** Keys are byte arrays in the file, so secret scanners do not read them as leaked credentials. */
    private fun bytes(array: JSONArray): ByteArray = ByteArray(array.length()) { array.getInt(it).toByte() }

    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }
}
