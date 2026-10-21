package org.autobutler.autofill

import org.autobutler.vaultcrypto.VaultCrypto
import org.autobutler.vaultcrypto.VaultHosts
import org.autobutler.vaultcrypto.VaultItemData
import org.autobutler.vaultcrypto.VaultItemKind
import java.security.MessageDigest

/** Why a fill request gets the "Open Quark" suggestion and fills nothing. */
enum class OpenQuarkReason {
    /** No cached key or no cache: biometric unlock is off, or the app has not synced the vault yet. */
    LOCKED,

    /** An app that is not a trusted browser. Matching apps by package is #3601, so nothing matches yet. */
    APP,

    /** A trusted browser that did not report one site for every field, so which site this is is not known. */
    UNSURE_SITE,
}

/** What the service answers a fill request with, before any key is used. */
sealed interface FillPlan<out Id> {
    /** Nothing to answer: no login fields, or Quark's own screen. */
    data object Ignore : FillPlan<Nothing>

    /** One suggestion that opens Quark and fills nothing. */
    data class OpenQuark<Id>(val fields: List<Id>, val reason: OpenQuarkReason) : FillPlan<Id>

    /**
     * One suggestion that names [host] and [requester] to the user, asks for the biometric, and then offers
     * the logins saved for [host].
     */
    data class Unlock<Id>(val form: LoginForm<Id>, val host: String, val requester: String) : FillPlan<Id>
}

/**
 * Decides a fill request (#3600) from the form, who asked, and whether a vault is stored, before anything is
 * decrypted. Every doubt ends in [FillPlan.OpenQuark] or [FillPlan.Ignore], never in a fill
 * (docs/design/native-autofill-vault.md, "Failure UX").
 */
object AutofillDecision {
    /**
     * The plan for [form], requested by [requester]. [ownPackage] is Quark's; [isTrustedBrowser] says whether
     * the requester's signature puts it on [TrustedBrowsers]; [hasVault] whether the store holds a key and a
     * cache. A domain is believed only from a trusted browser, and only when every field reported the same one.
     */
    fun <Id> plan(
        form: LoginForm<Id>,
        requester: String,
        ownPackage: String,
        isTrustedBrowser: () -> Boolean,
        hasVault: () -> Boolean,
    ): FillPlan<Id> {
        if (form.isEmpty || requester == ownPackage) return FillPlan.Ignore
        if (!isTrustedBrowser()) return FillPlan.OpenQuark(form.fields, OpenQuarkReason.APP)
        val host = form.webDomain?.let(VaultHosts::hostOf).orEmpty()
        if (form.domainConflict || host.isEmpty()) return FillPlan.OpenQuark(form.fields, OpenQuarkReason.UNSURE_SITE)
        if (!hasVault()) return FillPlan.OpenQuark(form.fields, OpenQuarkReason.LOCKED)
        return FillPlan.Unlock(form, host, requester)
    }
}

/** A login to offer: [name] and [username] label it, and [password] is filled only once it is chosen. */
class Credential(val name: String, val username: String, val password: String) {
    // Never prints the password into a log line or a crash report.
    override fun toString() = "Credential($name)"
}

/** What opening the vault after the biometric found. */
sealed interface UnlockOutcome {
    /** The logins saved for the site, in the cache's order. */
    data class Matches(val credentials: List<Credential>) : UnlockOutcome

    /** The vault opened and holds nothing for the site. */
    data object NoMatch : UnlockOutcome

    /** The key is not the one the cache was written under, so the app has to unlock with the password. */
    data object Stale : UnlockOutcome
}

/**
 * Opens a stored vault with its key after the biometric check and picks the logins for a host, matched as
 * `VaultController.entriesForUrl` matches them ([VaultHosts.matches]).
 */
class AutofillMatcher(private val crypto: VaultCrypto) {
    /**
     * The logins in [vault] for [host], opened with [vaultKey]. A key whose fingerprint is not the stored
     * one, or one that opens none of the cache's items, is [UnlockOutcome.Stale]: the vault was replaced, and
     * nothing is filled.
     */
    fun open(vault: StoredVault, vaultKey: ByteArray, host: String): UnlockOutcome {
        if (!MessageDigest.isEqual(crypto.fingerprint(vaultKey), vault.keyFile.fingerprint)) return UnlockOutcome.Stale
        val readable = vault.cache.items.filter { it.formatVersion == VaultCrypto.FORMAT_VERSION }
        val opened = readable.mapNotNull { item ->
            crypto.openItem(item.ciphertext, item.nonce, item.formatVersion, vaultKey)?.let { plaintext ->
                VaultItemData.decode(plaintext).also { plaintext.fill(0) }
            }
        }
        if (readable.isNotEmpty() && opened.isEmpty()) return UnlockOutcome.Stale
        val matches = opened
            .filter { it.kind == VaultItemKind.ENTRY && VaultHosts.matches(host, it.url) }
            .map { Credential(name = it.name, username = it.username, password = it.password) }
        return if (matches.isEmpty()) UnlockOutcome.NoMatch else UnlockOutcome.Matches(matches)
    }
}
