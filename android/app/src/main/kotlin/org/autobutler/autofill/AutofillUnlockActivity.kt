// cspell:words lazysodium goterl androidx vaultkeystore Parcelable
package org.autobutler.autofill

import android.app.Activity
import android.app.AlertDialog
import android.app.assist.AssistStructure
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.util.Log
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import androidx.annotation.RequiresApi
import com.goterl.lazysodium.LazySodiumAndroid
import com.goterl.lazysodium.SodiumAndroid
import org.autobutler.R
import org.autobutler.vaultcrypto.VaultCrypto
import org.autobutler.vaultkeystore.VaultKeystore
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The screen behind Quark's "unlock" suggestion (#3600). Not exported: the system launches it through the
 * fill response's `IntentSender`.
 *
 * It plans again from the structure the system hands it, then shows a strong-biometric prompt that names the
 * site and the app being filled ("Fill your bank.example login into Chrome?"), bound to the cached key's
 * [Cipher] by a [BiometricPrompt.CryptoObject], so only a real biometric opens the vault key. With the key it
 * opens the cached items, zeroes the key, and returns the logins for the site as the authentication result.
 *
 * Anything else fills nothing (docs/design/native-autofill-vault.md, "Failure UX"): a cancel closes quietly;
 * a locked, stale or changed key, or no login for the site, says so in plain words with one next step.
 */
@RequiresApi(Build.VERSION_CODES.O)
class AutofillUnlockActivity : Activity() {
    private val crypto by lazy { VaultCrypto(LazySodiumAndroid(SodiumAndroid())) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        // A screen recreated mid-prompt does not prompt again.
        if (savedInstanceState != null) return finish()
        try {
            start()
        } catch (e: Exception) {
            Log.w(TAG, "unlock failed: ${e.javaClass.simpleName}")
            explain(AutofillResponses.openQuarkText(this, OpenQuarkReason.LOCKED))
        }
    }

    private fun start() {
        @Suppress("DEPRECATION")
        val structure = intent.getParcelableExtra<AssistStructure>(AutofillManager.EXTRA_ASSIST_STRUCTURE)
        val plan = structure?.let { AutofillResponses.plan(this, it) }
        if (plan !is FillPlan.Unlock) {
            return if (plan is FillPlan.OpenQuark) explain(AutofillResponses.openQuarkText(this, plan.reason)) else finish()
        }
        val locked = AutofillResponses.openQuarkText(this, OpenQuarkReason.LOCKED)
        // #3595 caches a key only from Android 10, the first with BiometricManager.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return explain(locked)
        val vault = AutofillResponses.store(this).load() ?: return explain(locked)
        val key = KeyStore.getInstance(VaultKeystore.KEYSTORE).apply { load(null) }
            .getKey(VaultKeystore.ALIAS, null) as? SecretKey ?: return explain(locked)
        val cipher = Cipher.getInstance(VaultKeystore.TRANSFORMATION)
        try {
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, vault.keyFile.iv))
        } catch (_: KeyPermanentlyInvalidatedException) {
            // The app deletes the key the next time it reads it.
            return explain(getString(R.string.autofill_invalidated))
        }
        prompt(plan, vault, cipher)
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun prompt(plan: FillPlan.Unlock<AutofillId>, vault: StoredVault, cipher: Cipher) {
        val builder = BiometricPrompt.Builder(this)
            .setTitle(getString(R.string.autofill_prompt_title, plan.host, appLabel(plan.requester)))
            .setNegativeButton(getString(R.string.autofill_cancel), mainExecutor) { _, _ -> finish() }
            .setConfirmationRequired(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        }
        builder.build().authenticate(
            BiometricPrompt.CryptoObject(cipher),
            CancellationSignal(),
            mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    try {
                        fill(plan, vault, result.cryptoObject?.cipher ?: error("no cipher"))
                    } catch (_: KeyPermanentlyInvalidatedException) {
                        explain(getString(R.string.autofill_invalidated))
                    } catch (e: Exception) {
                        Log.w(TAG, "unlock failed: ${e.javaClass.simpleName}")
                        explain(AutofillResponses.openQuarkText(this@AutofillUnlockActivity, OpenQuarkReason.LOCKED))
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    when (VaultKeystore.failureOf(errorCode)) {
                        // Canceling is not an error: nothing to say.
                        "canceled" -> finish()
                        "lockedOut" -> explain(getString(R.string.autofill_locked_out), offerQuark = false)
                        "invalidated" -> explain(getString(R.string.autofill_invalidated))
                        else -> explain(AutofillResponses.openQuarkText(this@AutofillUnlockActivity, OpenQuarkReason.LOCKED))
                    }
                }

                // One face or finger not recognized: the prompt stays up for another try.
                override fun onAuthenticationFailed() {}
            },
        )
    }

    private fun fill(plan: FillPlan.Unlock<AutofillId>, vault: StoredVault, cipher: Cipher) {
        cipher.updateAAD(vault.account.toByteArray(Charsets.UTF_8))
        val vaultKey = cipher.doFinal(vault.keyFile.sealed)
        val outcome = try {
            AutofillMatcher(crypto).open(vault, vaultKey, plan.host)
        } finally {
            vaultKey.fill(0)
        }
        val response = (outcome as? UnlockOutcome.Matches)
            ?.let { AutofillResponses.forCredentials(this, plan.form, plan.host, it.credentials) }
        when {
            response != null -> {
                setResult(RESULT_OK, Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, response))
                finish()
            }
            outcome == UnlockOutcome.Stale -> explain(AutofillResponses.openQuarkText(this, OpenQuarkReason.LOCKED))
            else -> explain(getString(R.string.autofill_no_match, plan.host))
        }
    }

    /** Says [message] with one next step, opening Quark when [offerQuark], and closes the screen after. */
    private fun explain(message: String, offerQuark: Boolean = true) {
        val dialog = AlertDialog.Builder(this).setMessage(message)
        val open = AutofillResponses.openQuarkIntent(this)
        if (offerQuark && open != null) {
            dialog.setPositiveButton(R.string.autofill_open_quark) { _, _ -> startActivity(open) }
            dialog.setNegativeButton(R.string.autofill_cancel, null)
        } else {
            dialog.setPositiveButton(R.string.autofill_ok, null)
        }
        dialog.setOnDismissListener { finish() }.show()
    }

    /** The requesting app's name, or its package when it cannot be read. */
    private fun appLabel(packageName: String): CharSequence = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(packageName, 0))
    } catch (_: PackageManager.NameNotFoundException) {
        packageName
    }

    private companion object {
        const val TAG = "QuarkAutofill"
        const val GCM_TAG_BITS = 128
    }
}
