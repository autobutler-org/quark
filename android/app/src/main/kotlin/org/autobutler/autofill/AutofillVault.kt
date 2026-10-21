// cspell:words vaultkeystore
package org.autobutler.autofill

import org.autobutler.vaultkeystore.VaultKeyFile
import org.autobutler.vaultkeystore.VaultKeystore
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.util.Base64

/** One item of the ciphertext cache, as the Quark listed it. */
class CachedItem(val id: Long, val ciphertext: ByteArray, val nonce: ByteArray, val formatVersion: Int)

/**
 * The ciphertext cache the app writes (#3596, `lib/services/vault_cache.dart`): what `GET
 * /api/v0/vault/items` returned for one account, and nothing else.
 */
class AutofillCache(val items: List<CachedItem>, val keyFingerprint: ByteArray?) {
    companion object {
        /** The file format this code reads, `VaultCache.schema`. */
        const val SCHEMA = 1

        /** The directory in `noBackupFilesDir` the cache files sit in, `VaultCache.directoryName`. */
        const val DIRECTORY = "vault-autofill"

        /**
         * Reads a cache file, or null for one of another schema or one that does not parse: an unreadable
         * cache fills nothing. `keyFingerprint` is read when the file carries one.
         */
        fun decode(text: String): AutofillCache? = try {
            val json = JSONObject(text)
            if (json.getInt("schema") != SCHEMA) {
                null
            } else {
                val items = json.getJSONArray("items")
                AutofillCache(
                    items = (0 until items.length()).map { i ->
                        val item = items.getJSONObject(i)
                        CachedItem(
                            id = item.getLong("id"),
                            ciphertext = Base64.getDecoder().decode(item.getString("ciphertext")),
                            nonce = Base64.getDecoder().decode(item.getString("nonce")),
                            formatVersion = item.getInt("formatVersion"),
                        )
                    },
                    keyFingerprint = json.optString("keyFingerprint").takeIf { it.isNotEmpty() }
                        ?.let { Base64.getDecoder().decode(it) },
                )
            }
        } catch (_: JSONException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }
}

/** One account's cached vault key and its ciphertext cache: everything a fill reads before the prompt. */
class StoredVault(val account: String, val keyFile: VaultKeyFile.Parsed, val cache: AutofillCache)

/** Where the service finds the [StoredVault]. The JVM tests pass a fake. */
fun interface AutofillStore {
    /** The stored vault, or null when there is none to fill from. */
    fun load(): StoredVault?
}

/**
 * The [AutofillStore] on disk, under the app's `noBackupFilesDir` ([noBackupDir]): the one cached key
 * #3595 keeps in `vault-key/` and the same account's cache in `vault-autofill/`. Anything else, such as no
 * key, two keys, a cache for another account, or a cache whose fingerprint is not the key's, is no vault.
 */
class DiskAutofillStore(private val noBackupDir: File) : AutofillStore {
    override fun load(): StoredVault? {
        val keyFiles = File(noBackupDir, VaultKeystore.DIRECTORY).listFiles()
            ?.filter { it.isFile && it.name.endsWith(KEY_SUFFIX) }
            .orEmpty()
        val keyFile = keyFiles.singleOrNull() ?: return null
        val account = keyFile.name.removeSuffix(KEY_SUFFIX)
        if (!VaultKeyFile.isAccountKey(account)) return null
        val parsed = VaultKeyFile.decode(keyFile.readBytes()) ?: return null
        val cacheFile = File(File(noBackupDir, AutofillCache.DIRECTORY), "$account.json")
        if (!cacheFile.isFile) return null
        val cache = AutofillCache.decode(cacheFile.readText()) ?: return null
        val cachedFingerprint = cache.keyFingerprint
        if (cachedFingerprint != null && !cachedFingerprint.contentEquals(parsed.fingerprint)) return null
        return StoredVault(account, parsed, cache)
    }

    private companion object {
        const val KEY_SUFFIX = ".bin"
    }
}
