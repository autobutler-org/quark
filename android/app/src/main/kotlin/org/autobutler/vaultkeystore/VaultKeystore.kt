// cspell:words lazysodium goterl strongbox vaultkeystore keyguard androidx
package org.autobutler.vaultkeystore

import android.app.Activity
import android.app.KeyguardManager
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Log
import androidx.annotation.RequiresApi
import com.goterl.lazysodium.LazySodiumAndroid
import com.goterl.lazysodium.SodiumAndroid
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.autobutler.vaultcrypto.VaultCrypto
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

/**
 * The vault key behind a strong biometric (#3595), on the `org.autobutler/vault_keystore` channel that
 * `lib/services/vault_biometric.dart` speaks (docs/design/native-autofill-vault.md, Decision 2).
 *
 * One AES-256-GCM key, [ALIAS] in `AndroidKeyStore`, needs a Class 3 biometric for every use and is
 * invalidated by a new enrollment; it is never offered with the device credential, and never with a Class 2
 * ("weak") biometric. It seals the account's vault key into a [VaultKeyFile] in `noBackupFilesDir`, one
 * account at a time. Every use goes through a framework [BiometricPrompt] bound to the [Cipher] by a
 * [BiometricPrompt.CryptoObject], so a prompt that only reports success cannot use the key. A key the OS
 * invalidated is deleted with every file, and a key whose fingerprint ([VaultCrypto.fingerprint]) is not
 * the stored one is deleted with its file.
 *
 * Offered from Android 10 (API 29), the first with [BiometricManager], and only where the key is
 * hardware-backed. Channel errors carry a code the Dart side reads as a `VaultBiometricFailure`, and never a
 * message: nothing here puts key material, or an exception's text, into a reply or the log.
 */
class VaultKeystore(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "org.autobutler/vault_keystore"
        const val ALIAS = "quark_vault_autofill_v1"

        /** The keystore [ALIAS] lives in. */
        const val KEYSTORE = "AndroidKeyStore"

        /** How [ALIAS] seals a vault key into a [VaultKeyFile]. */
        const val TRANSFORMATION = "AES/GCM/NoPadding"

        /** The directory in `noBackupFilesDir` the [VaultKeyFile]s sit in. */
        const val DIRECTORY = "vault-key"
        private const val TAG = "VaultKeystore"

        /** The failure code a [BiometricPrompt] error code means, as the Dart side reads it. */
        fun failureOf(errorCode: Int): String = when (errorCode) {
            BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED,
            BiometricPrompt.BIOMETRIC_ERROR_CANCELED,
            -> "canceled"
            BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT,
            BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT_PERMANENT,
            -> "lockedOut"
            BiometricPrompt.BIOMETRIC_ERROR_NO_BIOMETRICS -> "invalidated"
            BiometricPrompt.BIOMETRIC_ERROR_HW_UNAVAILABLE,
            BiometricPrompt.BIOMETRIC_ERROR_HW_NOT_PRESENT,
            -> "unavailable"
            else -> "failed"
        }
    }

    private val directory get() = File(activity.noBackupFilesDir, DIRECTORY)
    private val crypto by lazy { VaultCrypto(LazySodiumAndroid(SodiumAndroid())) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = Reply(result)
        try {
            when (call.method) {
                "support" -> reply.success(support())
                "storedFingerprint" -> reply.success(readFile(account(call))?.fingerprint)
                "store", "read" -> when {
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.Q -> reply.error("unavailable")
                    call.method == "store" -> store(call, reply)
                    else -> read(call, reply)
                }
                "delete" -> {
                    delete(call.argument<String>("account"))
                    reply.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.w(TAG, "${call.method} failed: ${e.javaClass.simpleName}")
            reply.error("failed")
        }
    }

    private fun support(): Map<String, String> {
        val status = when {
            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q -> "unavailable"
            !activity.getSystemService(KeyguardManager::class.java).isDeviceSecure -> "notEnrolled"
            else -> when (canAuthenticate()) {
                BiometricManager.BIOMETRIC_SUCCESS -> "available"
                BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "notEnrolled"
                else -> "unavailable"
            }
        }
        return mapOf("status" to status, "kind" to "biometrics")
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun canAuthenticate(): Int {
        val manager = activity.getSystemService(BiometricManager::class.java)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        } else {
            // Android 10's BiometricPrompt takes strong biometrics only.
            @Suppress("DEPRECATION")
            manager.canAuthenticate()
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun store(call: MethodCall, reply: Reply) {
        val account = account(call)
        val vaultKey = call.argument<ByteArray>("key")
        val fingerprint = call.argument<ByteArray>("fingerprint")
        if (vaultKey == null || fingerprint == null ||
            vaultKey.size != VaultKeyFile.VAULT_KEY_BYTES ||
            fingerprint.size != VaultKeyFile.FINGERPRINT_BYTES
        ) {
            vaultKey?.fill(0)
            return reply.error("failed")
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        try {
            cipher.init(Cipher.ENCRYPT_MODE, keyForStore() ?: return reply.error("unavailable"))
        } catch (e: KeyPermanentlyInvalidatedException) {
            // Enrolled since the key was made: start again with a new one.
            delete(null)
            cipher.init(Cipher.ENCRYPT_MODE, keyForStore() ?: return reply.error("unavailable"))
        }
        prompt(call, cipher, reply, onDone = { vaultKey.fill(0) }) { authenticated ->
            authenticated.updateAAD(account.toByteArray(Charsets.UTF_8))
            val sealed = authenticated.doFinal(vaultKey)
            writeOnly(account, VaultKeyFile.encode(fingerprint, authenticated.iv, sealed))
            reply.success(null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun read(call: MethodCall, reply: Reply) {
        val account = account(call)
        val file = readFile(account) ?: return reply.error("missing")
        val key = existingKey()
        if (key == null) {
            delete(null)
            return reply.error("missing")
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        try {
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, file.iv))
        } catch (e: KeyPermanentlyInvalidatedException) {
            delete(null)
            return reply.error("invalidated")
        }
        prompt(call, cipher, reply) { authenticated ->
            authenticated.updateAAD(account.toByteArray(Charsets.UTF_8))
            val vaultKey = authenticated.doFinal(file.sealed)
            if (!MessageDigest.isEqual(crypto.fingerprint(vaultKey), file.fingerprint)) {
                vaultKey.fill(0)
                delete(account)
                return@prompt reply.error("stale")
            }
            // The codec copies the reply as it is sent, so the key can be zeroed after.
            reply.success(mapOf("key" to vaultKey, "fingerprint" to file.fingerprint))
            vaultKey.fill(0)
        }
    }

    /**
     * Shows the biometric prompt for [cipher] with the call's words, and runs [use] with the authenticated
     * cipher. A cancel, a lockout or a hardware failure replies with its code; [onDone] runs either way.
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun prompt(
        call: MethodCall,
        cipher: Cipher,
        reply: Reply,
        onDone: () -> Unit = {},
        use: (Cipher) -> Unit,
    ) {
        val executor = activity.mainExecutor
        val builder = BiometricPrompt.Builder(activity)
            .setTitle(call.argument<String>("title") ?: "")
            .setSubtitle(call.argument<String>("reason") ?: "")
            .setNegativeButton(call.argument<String>("cancel") ?: "Cancel", executor) { _, _ ->
                onDone()
                reply.error("canceled")
            }
            .setConfirmationRequired(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        }
        builder.build().authenticate(
            BiometricPrompt.CryptoObject(cipher),
            CancellationSignal(),
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    try {
                        use(result.cryptoObject?.cipher ?: return reply.error("failed"))
                    } catch (e: KeyPermanentlyInvalidatedException) {
                        delete(null)
                        reply.error("invalidated")
                    } catch (e: Exception) {
                        Log.w(TAG, "keystore use failed: ${e.javaClass.simpleName}")
                        reply.error("failed")
                    } finally {
                        onDone()
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    onDone()
                    reply.error(failureOf(errorCode))
                }

                // One face or finger not recognized: the prompt stays up for another try.
                override fun onAuthenticationFailed() {}
            },
        )
    }

    private fun account(call: MethodCall): String {
        val account = call.argument<String>("account")
        require(VaultKeyFile.isAccountKey(account)) { "not an account key" }
        return account!!
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun existingKey(): SecretKey? = keyStore().getKey(ALIAS, null) as? SecretKey

    /** The key to seal under, made if there is none, or null where it would not be hardware-backed. */
    private fun keyForStore(): SecretKey? {
        val key = existingKey() ?: makeKey()
        if (!hardwareBacked(key)) {
            keyStore().deleteEntry(ALIAS)
            Log.i(TAG, "keystore has no secure hardware; biometric unlock not offered")
            return null
        }
        return key
    }

    private fun makeKey(): SecretKey {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        ) {
            try {
                return generate(strongBox = true).also { Log.i(TAG, "vault key sealed in StrongBox") }
            } catch (e: StrongBoxUnavailableException) {
                // Falls through to the TEE.
            }
        }
        return generate(strongBox = false).also { Log.i(TAG, "vault key sealed in the TEE") }
    }

    private fun generate(strongBox: Boolean): SecretKey {
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            spec.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            @Suppress("DEPRECATION")
            spec.setUserAuthenticationValidityDurationSeconds(-1)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            spec.setUnlockedDeviceRequired(true)
            if (strongBox) spec.setIsStrongBoxBacked(true)
        }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).run {
            init(spec.build())
            generateKey()
        }
    }

    private fun hardwareBacked(key: SecretKey): Boolean {
        val info = SecretKeyFactory.getInstance(key.algorithm, KEYSTORE).getKeySpec(key, KeyInfo::class.java) as KeyInfo
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            info.securityLevel == KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT ||
                info.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX
        } else {
            @Suppress("DEPRECATION")
            info.isInsideSecureHardware
        }
    }

    private fun readFile(account: String): VaultKeyFile.Parsed? {
        val file = File(directory, VaultKeyFile.fileName(account))
        return if (file.isFile) VaultKeyFile.decode(file.readBytes()) else null
    }

    /** Writes [account]'s file through a rename and deletes every other account's: one account at a time. */
    private fun writeOnly(account: String, bytes: ByteArray) {
        val name = VaultKeyFile.fileName(account)
        directory.mkdirs()
        val temp = File(directory, "$name.tmp")
        temp.writeBytes(bytes)
        check(temp.renameTo(File(directory, name))) { "rename failed" }
        directory.listFiles()?.filter { it.name != name }?.forEach { it.delete() }
    }

    /** Deletes [account]'s file, or every file and the Keystore key for null. */
    private fun delete(account: String?) {
        if (account == null) {
            directory.deleteRecursively()
            keyStore().deleteEntry(ALIAS)
            return
        }
        File(directory, VaultKeyFile.fileName(account)).delete()
    }

    /** Replies once: a prompt's callbacks and the method's own failure path cannot both answer. */
    private class Reply(private val result: MethodChannel.Result) {
        private val answered = AtomicBoolean(false)

        fun success(value: Any?) {
            if (answered.compareAndSet(false, true)) result.success(value)
        }

        fun error(code: String) {
            if (answered.compareAndSet(false, true)) result.error(code, null, null)
        }
    }
}
