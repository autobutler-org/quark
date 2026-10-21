// cspell:words sbrowser emmx duckduckgo vivaldi gstatic
package org.autobutler.autofill

import java.security.MessageDigest

/**
 * The browsers whose `webDomain` the service believes (#3600, docs/design/native-autofill-vault.md, "Android
 * phishing through `webDomain`"). Any app can put `webDomain = "bank.example"` on its own login field, so a
 * domain counts only from a package named here whose every signing certificate is one listed for it. Any
 * other app is matched by its package, which is #3601; until then it matches nothing.
 *
 * The certificates are the SHA-256 digests Google publishes for these packages in its list of privileged
 * browsers (https://www.gstatic.com/gpm-passkeys-privileged-apps/apps.json). A browser missing here is not
 * filled; adding one is adding its package and digests, and its package to the manifest's `<queries>`.
 */
object TrustedBrowsers {
    /** Each trusted package and the certificate digests, colon-separated uppercase hex, it may be signed with. */
    val certificates: Map<String, Set<String>> = mapOf(
        "com.android.chrome" to setOf(
            "F0:FD:6C:5B:41:0F:25:CB:25:C3:B5:33:46:C8:97:2F:AE:30:F8:EE:74:11:DF:91:04:80:AD:6B:2D:60:DB:83",
            "19:75:B2:F1:71:77:BC:89:A5:DF:F3:1F:9E:64:A6:CA:E2:81:A5:3D:C1:D1:D5:9B:1D:14:7F:E1:C8:2A:FA:00",
        ),
        "org.mozilla.firefox" to setOf(
            "A7:8B:62:A5:16:5B:44:94:B2:FE:AD:9E:76:A2:80:D2:2D:93:7F:EE:62:51:AE:CE:59:94:46:B2:EA:31:9B:04",
        ),
        "org.mozilla.focus" to setOf(
            "62:03:A4:73:BE:36:D6:4E:E3:7F:87:FA:50:0E:DB:C7:9E:AB:93:06:10:AB:9B:9F:A4:CA:7D:5C:1F:1B:4F:FC",
        ),
        "com.sec.android.app.sbrowser" to setOf(
            "34:DF:0E:7A:9F:1C:F1:89:2E:45:C0:56:B4:97:3C:D8:1C:CF:14:8A:40:50:D1:1A:EA:4A:C5:A6:5F:90:0A:42",
            "C8:A2:E9:BC:CF:59:7C:2F:B6:DC:66:BE:E2:93:FC:13:F2:FC:47:EC:77:BC:6B:2B:0D:52:C1:1F:51:19:2A:B8",
        ),
        "com.microsoft.emmx" to setOf(
            "01:E1:99:97:10:A8:2C:27:49:B4:D5:0C:44:5D:C8:5D:67:0B:61:36:08:9D:0A:76:6A:73:82:7C:82:A1:EA:C9",
        ),
        "com.brave.browser" to setOf(
            "9C:2D:B7:05:13:51:5F:DB:FB:BC:58:5B:3E:DF:3D:71:23:D4:DC:67:C9:4F:FD:30:63:61:C1:D7:9B:BF:18:AC",
        ),
        "com.duckduckgo.mobile.android" to setOf(
            "BB:7B:B3:1C:57:3C:46:A1:DA:7F:C5:C5:28:A6:AC:F4:32:10:84:56:FE:EC:50:81:0C:7F:33:69:4E:B3:D2:D4",
        ),
        "com.vivaldi.browser" to setOf(
            "E8:A7:85:44:65:5B:A8:C0:98:17:F7:32:76:8F:56:89:B1:66:2E:C4:B2:BC:5A:0B:C0:EC:13:8D:33:CA:3D:1E",
        ),
        "com.opera.browser" to setOf(
            "5D:6A:FB:F8:7F:65:2A:F0:46:47:AD:A0:DF:63:4C:F2:23:70:90:0B:16:4B:09:D5:0B:D2:3A:A2:CB:52:85:B8",
        ),
    )

    /**
     * Whether [packageName], signed with the certificates [signers] (each one's DER bytes), is a trusted
     * browser: it is listed in [allowlist], it has at least one signer, and every signer is one listed for it.
     */
    fun isTrusted(
        packageName: String,
        signers: List<ByteArray>,
        allowlist: Map<String, Set<String>> = certificates,
    ): Boolean {
        val allowed = allowlist[packageName] ?: return false
        return signers.isNotEmpty() && signers.all { digestOf(it) in allowed }
    }

    /** [certificate]'s SHA-256 digest as colon-separated uppercase hex. */
    fun digestOf(certificate: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(certificate).joinToString(":") { "%02X".format(it) }
}
