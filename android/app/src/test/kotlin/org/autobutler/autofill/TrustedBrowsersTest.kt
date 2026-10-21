package org.autobutler.autofill

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Which apps' web domains are believed (#3600): listed packages, signed only with their listed certificates. */
class TrustedBrowsersTest {
    private val cert = "a certificate".toByteArray()
    private val other = "another certificate".toByteArray()

    private fun trusting(vararg certs: ByteArray) = TrustedBrowsers.certificates + mapOf(
        "test.browser" to certs.map(TrustedBrowsers::digestOf).toSet(),
    )

    @Test
    fun `digests are colon-separated uppercase SHA-256`() {
        // SHA-256 of the empty input.
        assertEquals(
            "E3:B0:C4:42:98:FC:1C:14:9A:FB:F4:C8:99:6F:B9:24:27:AE:41:E4:64:9B:93:4C:A4:95:99:1B:78:52:B8:55",
            TrustedBrowsers.digestOf(ByteArray(0)),
        )
    }

    @Test
    fun `an unlisted package is never trusted`() {
        assertFalse(TrustedBrowsers.isTrusted("com.evil.app", listOf(cert)))
    }

    @Test
    fun `a listed package signed with another certificate is not trusted`() {
        assertFalse(TrustedBrowsers.isTrusted("com.android.chrome", listOf(cert)))
    }

    @Test
    fun `a listed package with no signers is not trusted`() {
        assertFalse(TrustedBrowsers.isTrusted("com.android.chrome", emptyList()))
    }

    @Test
    fun `every signer has to be listed`() {
        val allowed = trusting(cert)
        assertTrue(TrustedBrowsers.isTrusted("test.browser", listOf(cert), allowed))
        assertFalse(TrustedBrowsers.isTrusted("test.browser", listOf(cert, other), allowed))
    }

    @Test
    fun `every listed digest is well formed`() {
        for ((name, digests) in TrustedBrowsers.certificates) {
            for (digest in digests) assertTrue(name, Regex("([0-9A-F]{2}:){31}[0-9A-F]{2}").matches(digest))
        }
    }
}
