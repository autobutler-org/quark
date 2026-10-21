// cspell:words userinfo badexample
package org.autobutler.vaultcrypto

/**
 * Which site a vault entry is for, read the way the app reads it (#3597): [hostOf] is `VaultItemData.hostOf`
 * (`lib/models/vault_item.dart`) and [matches] is `VaultController.entriesForUrl`.
 *
 * `hostOf` reads a URL with Dart's `Uri.tryParse`, so this follows that parser's rules rather than
 * `java.net.URI`'s: a backslash ends the authority, the userinfo ends at the first `@`, an escape of an
 * unreserved character is decoded, any other character a host may not hold makes the host empty, and a port
 * is whatever Dart's `int.tryParse` accepts. The `hosts` table in `test/fixtures/vault_vectors.json` pins it.
 */
object VaultHosts {
    /** The lowercased host of [url], reading a URL with no scheme as https; empty when there is none. */
    fun hostOf(url: String): String {
        val trimmed = url.trim()
        if (trimmed.isEmpty()) return ""
        val s = (if (trimmed.contains("://")) trimmed else "https://$trimmed").replace('\\', '/')

        val schemeEnd = s.indexOfFirst { it in ":/?#" }
        val rest = if (schemeEnd > 0 && s[schemeEnd] == ':') {
            if (!isScheme(s.substring(0, schemeEnd))) return ""
            s.substring(schemeEnd + 1)
        } else {
            s
        }
        if (!rest.startsWith("//")) return ""
        var authority = rest.drop(2).takeWhile { it !in "/?#" }

        val at = authority.indexOf('@')
        if (at >= 0) {
            val userInfo = authority.substring(0, at)
            if ('[' in userInfo || ']' in userInfo) return ""
            authority = authority.substring(at + 1)
        }

        val host: String
        val port: String
        if (authority.startsWith('[')) {
            val close = authority.indexOf(']')
            if (close < 0) return ""
            host = authority.substring(1, close)
            val after = authority.substring(close + 1)
            if (after.isNotEmpty() && !after.startsWith(':')) return ""
            port = after.drop(1)
            if (!isIpv6(host)) return ""
        } else {
            val colon = authority.indexOf(':')
            host = decodeRegName(if (colon < 0) authority else authority.substring(0, colon)) ?: return ""
            port = if (colon < 0) "" else authority.substring(colon + 1)
        }
        if (port.isNotEmpty() && !PORT.matches(port.trim())) return ""
        return host.lowercase()
    }

    /**
     * Whether an entry saved for [site] fills on the page at [url]: the two hosts are the same, or [site]'s is
     * a parent domain of [url]'s, so `accounts.example.com` matches `example.com` and `badexample.com` does
     * not.
     */
    fun matches(url: String, site: String): Boolean {
        val host = hostOf(url)
        val siteHost = hostOf(site)
        return host.isNotEmpty() && siteHost.isNotEmpty() && (host == siteHost || host.endsWith(".$siteHost"))
    }

    private fun isScheme(scheme: String): Boolean =
        scheme[0].isAsciiLetter() && scheme.all { it.isAsciiLetter() || it in '0'..'9' || it in "+-." }

    /** A registered name with escapes of unreserved characters decoded, or null when Dart would escape it. */
    private fun decodeRegName(name: String): String? {
        val out = StringBuilder()
        var i = 0
        while (i < name.length) {
            val c = name[i]
            if (c == '%' && i + 2 < name.length) {
                val decoded = if (name[i + 1].isHex() && name[i + 2].isHex()) {
                    name.substring(i + 1, i + 3).toInt(16).toChar()
                } else {
                    null
                }
                if (decoded != null && decoded.isUnreserved()) {
                    out.append(decoded)
                    i += 3
                    continue
                }
            }
            if (!c.isUnreserved() && c !in SUB_DELIMS) return null
            out.append(c)
            i++
        }
        return out.toString()
    }

    private fun isIpv6(host: String): Boolean {
        val double = host.indexOf("::")
        if (double < 0) return ipv6Groups(host) == 8
        if (host.indexOf("::", double + 1) >= 0) return false
        val left = host.substring(0, double)
        if ('.' in left) return false
        val a = ipv6Groups(left) ?: return false
        val b = ipv6Groups(host.substring(double + 2)) ?: return false
        return a + b <= 7
    }

    /** How many 16-bit groups [part] holds, a trailing dotted IPv4 counting two; null when it is malformed. */
    private fun ipv6Groups(part: String): Int? {
        if (part.isEmpty()) return 0
        val groups = part.split(':')
        var n = 0
        for ((i, group) in groups.withIndex()) {
            n += if (i == groups.lastIndex && '.' in group) {
                val quad = group.split('.')
                val valid = quad.size == 4 &&
                    quad.all { q -> q.isNotEmpty() && q.all { it in '0'..'9' } && q.toBigInteger() <= 255.toBigInteger() }
                if (!valid) return null
                2
            } else if (group.length in 1..4 && group.all { it.isHex() }) {
                1
            } else {
                return null
            }
        }
        return n
    }

    private fun Char.isAsciiLetter() = this in 'a'..'z' || this in 'A'..'Z'

    private fun Char.isHex() = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'

    private fun Char.isUnreserved() = isAsciiLetter() || this in '0'..'9' || this in "-._~"

    private const val SUB_DELIMS = "!$&'()*+,;="

    private val PORT = Regex("[+-]?([0-9]+|0[xX][0-9a-fA-F]+)")
}
