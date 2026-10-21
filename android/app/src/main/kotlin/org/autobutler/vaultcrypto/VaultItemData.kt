// cspell:words totp
package org.autobutler.vaultcrypto

import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/** Entry or folder, as `VaultItemKind` names them in the item JSON. */
enum class VaultItemKind(val jsonName: String) {
    /** A saved login. */
    ENTRY("entry"),

    /** A folder entries are filed in. */
    FOLDER("folder"),
}

/** A name and value the user added to an entry, `VaultCustomField`. */
data class VaultCustomField(val label: String, val value: String, val hidden: Boolean)

/**
 * One decrypted vault item, read as `VaultItemData.fromJson` (`lib/models/vault_item.dart`) reads it (#3597):
 * a missing or null field is empty, an unknown key is ignored, and an unknown `kind` or a field of the wrong
 * type is refused, since guessing would lose what a newer app wrote. The `itemJson` cases in
 * `test/fixtures/vault_vectors.json` pin it.
 */
data class VaultItemData(
    val kind: VaultItemKind,
    val name: String,
    val url: String,
    val username: String,
    val password: String,
    val notes: String,
    val totpSecret: String,
    val customFields: List<VaultCustomField>,
    val folderId: Long?,
) {
    /** [url]'s host as [VaultHosts.hostOf] reads it. */
    val urlHost: String get() = VaultHosts.hostOf(url)

    companion object {
        /** Reads an item's UTF-8 JSON, what [VaultCrypto.openItem] returns. Null when the app would refuse it. */
        fun decode(plaintext: ByteArray): VaultItemData? = try {
            val text = Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(plaintext))
                .toString()
            fromJson(JSONObject(text))
        } catch (_: CharacterCodingException) {
            null
        } catch (_: org.json.JSONException) {
            null
        } catch (_: ClassCastException) {
            null
        }

        private fun fromJson(json: JSONObject): VaultItemData? {
            val kindName = json.field<String>("kind") ?: VaultItemKind.ENTRY.jsonName
            val kind = VaultItemKind.entries.firstOrNull { it.jsonName == kindName } ?: return null
            val fields = json.field<JSONArray>("customFields")
            return VaultItemData(
                kind = kind,
                name = json.field<String>("name") ?: "",
                url = json.field<String>("url") ?: "",
                username = json.field<String>("username") ?: "",
                password = json.field<String>("password") ?: "",
                notes = json.field<String>("notes") ?: "",
                totpSecret = json.field<String>("totpSecret") ?: "",
                customFields = (0 until (fields?.length() ?: 0)).map { i ->
                    val field = fields!!.get(i) as JSONObject
                    VaultCustomField(
                        label = field.field<String>("label") ?: "",
                        value = field.field<String>("value") ?: "",
                        hidden = field.field<Boolean>("hidden") ?: false,
                    )
                },
                folderId = json.field<Number>("folderId")?.toLong(),
            )
        }

        /** [key]'s value as a [T], null when it is missing or null; a value of another type throws. */
        private inline fun <reified T> JSONObject.field(key: String): T? {
            val value = opt(key)
            return if (value == null || value == JSONObject.NULL) null else value as T
        }
    }
}
