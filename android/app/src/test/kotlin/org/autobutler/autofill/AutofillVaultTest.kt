// cspell:words lazysodium goterl vaultkeystore badexample badbank
package org.autobutler.autofill

import com.goterl.lazysodium.LazySodiumJava
import com.goterl.lazysodium.SodiumJava
import org.autobutler.vaultcrypto.VaultCrypto
import org.autobutler.vaultkeystore.VaultKeyFile
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.Base64

/**
 * Reading the stored vault (#3600) and opening it after the biometric: the cache and key files on disk, the
 * logins matched for a site as `entriesForUrl` matches them, and every way it fails closed.
 */
class AutofillVaultTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val crypto = VaultCrypto(LazySodiumJava(SodiumJava()))
    private val vaultKey = ByteArray(32) { (it * 3).toByte() }
    private val account = "acct_" + "0123456789abcdef".repeat(2)

    private fun item(id: Long, json: JSONObject, key: ByteArray = vaultKey): JSONObject {
        val sealed = crypto.sealItem(json.toString().toByteArray(), key)
        return JSONObject()
            .put("id", id)
            .put("ciphertext", Base64.getEncoder().encodeToString(sealed.ciphertext))
            .put("nonce", Base64.getEncoder().encodeToString(sealed.nonce))
            .put("formatVersion", sealed.formatVersion)
            .put("updatedAt", "2026-10-20T12:00:00Z")
    }

    private fun entry(name: String, url: String, username: String = "me", password: String = "hunter2") =
        JSONObject().put("kind", "entry").put("name", name).put("url", url)
            .put("username", username).put("password", password)

    private fun cacheJson(vararg items: JSONObject, fingerprint: ByteArray? = null) = JSONObject()
        .put("schema", 1)
        .put("host", "https://quark.local")
        .put("username", "me")
        .put("syncedAt", "2026-10-20T12:00:00Z")
        .put("items", JSONArray(items.toList()))
        .apply { fingerprint?.let { put("keyFingerprint", Base64.getEncoder().encodeToString(it)) } }

    private fun vault(vararg items: JSONObject, fingerprint: ByteArray = crypto.fingerprint(vaultKey)) = StoredVault(
        account,
        VaultKeyFile.Parsed(fingerprint, ByteArray(12), ByteArray(48)),
        AutofillCache.decode(cacheJson(*items).toString())!!,
    )

    private fun writeStore(
        cache: String? = cacheJson().toString(),
        keyAccount: String = account,
        cacheAccount: String = account,
        fingerprint: ByteArray = crypto.fingerprint(vaultKey),
    ): DiskAutofillStore {
        val root = temp.newFolder()
        File(root, "vault-key").mkdirs()
        File(root, "vault-key/${VaultKeyFile.fileName(keyAccount)}")
            .writeBytes(VaultKeyFile.encode(fingerprint, ByteArray(12), ByteArray(48)))
        if (cache != null) {
            File(root, "vault-autofill").mkdirs()
            File(root, "vault-autofill/$cacheAccount.json").writeText(cache)
        }
        return DiskAutofillStore(root)
    }

    @Test
    fun `logins for the site and its subdomains are offered, lookalikes are not`() {
        val outcome = AutofillMatcher(crypto).open(
            vault(
                item(1, entry("Bank", "https://bank.example/login")),
                item(2, entry("Lookalike", "badbank.example")),
                item(3, JSONObject().put("kind", "folder").put("name", "Bank").put("url", "bank.example")),
                item(4, entry("Other", "other.example")),
            ),
            vaultKey,
            "accounts.bank.example",
        ) as UnlockOutcome.Matches
        assertEquals(listOf("Bank"), outcome.credentials.map { it.name })
        assertEquals("me", outcome.credentials[0].username)
        assertEquals("hunter2", outcome.credentials[0].password)
    }

    @Test
    fun `an entry for a subdomain does not fill its parent`() {
        val outcome = AutofillMatcher(crypto).open(vault(item(1, entry("Bank", "accounts.bank.example"))), vaultKey, "bank.example")
        assertEquals(UnlockOutcome.NoMatch, outcome)
    }

    @Test
    fun `no login for the site is a no match`() {
        assertEquals(
            UnlockOutcome.NoMatch,
            AutofillMatcher(crypto).open(vault(item(1, entry("Other", "other.example"))), vaultKey, "bank.example"),
        )
        assertEquals(UnlockOutcome.NoMatch, AutofillMatcher(crypto).open(vault(), vaultKey, "bank.example"))
    }

    @Test
    fun `a key whose fingerprint is not the stored one fills nothing`() {
        val outcome = AutofillMatcher(crypto).open(
            vault(item(1, entry("Bank", "bank.example")), fingerprint = ByteArray(16)),
            vaultKey,
            "bank.example",
        )
        assertEquals(UnlockOutcome.Stale, outcome)
    }

    @Test
    fun `a key that opens none of the items fills nothing`() {
        val otherKey = ByteArray(32) { 9 }
        val outcome = AutofillMatcher(crypto).open(
            vault(item(1, entry("Bank", "bank.example"), key = otherKey)),
            vaultKey,
            "bank.example",
        )
        assertEquals(UnlockOutcome.Stale, outcome)
    }

    @Test
    fun `a credential never prints its password`() {
        assertFalse(Credential("Bank", "me", "hunter2").toString().contains("hunter2"))
    }

    @Test
    fun `the store reads the key and the same account's cache`() {
        val stored = writeStore(cacheJson(item(1, entry("Bank", "bank.example"))).toString()).load()
        assertNotNull(stored)
        assertEquals(account, stored!!.account)
        assertEquals(1, stored.cache.items.size)
    }

    @Test
    fun `the store has nothing without a key, a cache, or with a cache for another account`() {
        assertNull(DiskAutofillStore(temp.newFolder()).load())
        assertNull(writeStore(cache = null).load())
        assertNull(writeStore(cacheAccount = "acct_" + "f".repeat(32)).load())
    }

    @Test
    fun `the store refuses an unreadable cache or one of another schema`() {
        assertNull(writeStore(cache = "not json").load())
        assertNull(writeStore(cache = cacheJson().put("schema", 2).toString()).load())
        assertNull(writeStore(cache = cacheJson().put("items", JSONArray().put(JSONObject().put("id", 1))).toString()).load())
    }

    @Test
    fun `the store refuses a cache written under another key`() {
        assertNull(writeStore(cache = cacheJson(fingerprint = ByteArray(16) { 1 }).toString()).load())
        assertNotNull(writeStore(cache = cacheJson(fingerprint = crypto.fingerprint(vaultKey)).toString()).load())
    }

    @Test
    fun `the store refuses two cached keys`() {
        val store = writeStore()
        val root = File(temp.root, temp.root.list()!!.single())
        File(root, "vault-key/acct_${"e".repeat(32)}.bin")
            .writeBytes(VaultKeyFile.encode(ByteArray(16), ByteArray(12), ByteArray(48)))
        assertNull(store.load())
    }
}
