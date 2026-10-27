import Foundation

/// Which site a vault entry is for, read the way the app reads it (#3597): ``hostOf(_:)`` is
/// `VaultItemData.hostOf` (`lib/models/vault_item.dart`) and ``matches(url:site:)`` is
/// `VaultController.entriesForUrl`.
///
/// `hostOf` reads a URL with Dart's `Uri.tryParse`, so this follows that parser's rules rather than
/// Foundation's: a backslash ends the authority, the userinfo ends at the first `@`, an escape of an
/// unreserved character is decoded, any other character a host may not hold makes the host empty, and a port
/// is whatever Dart's `int.tryParse` accepts. The `hosts` table in `test/fixtures/vault_vectors.json` pins it.
/// It works on Unicode scalars, as Dart works on code units, so a combining mark never merges with a
/// delimiter.
public enum VaultHosts {
    /// The lowercased host of `url`, reading a URL with no scheme as https; empty when there is none.
    public static func hostOf(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        let s = withScheme.unicodeScalars.map { $0 == "\\" ? "/" : $0 }

        var rest = s[...]
        if let end = s.firstIndex(where: { ":/?#".unicodeScalars.contains($0) }), end > 0, s[end] == ":" {
            guard isScheme(s[..<end]) else { return "" }
            rest = s[(end + 1)...]
        }
        guard rest.starts(with: ["/", "/"]) else { return "" }
        var authority = rest.dropFirst(2).prefix(while: { !"/?#".unicodeScalars.contains($0) })

        if let at = authority.firstIndex(of: "@") {
            if authority[..<at].contains("[") || authority[..<at].contains("]") { return "" }
            authority = authority[(at + 1)...]
        }

        let host: String
        let port: ArraySlice<Unicode.Scalar>
        if authority.first == "[" {
            guard let close = authority.firstIndex(of: "]") else { return "" }
            let after = authority[(close + 1)...]
            if let first = after.first, first != ":" { return "" }
            port = after.dropFirst()
            host = string(authority[(authority.startIndex + 1)..<close])
            guard isIpv6(host) else { return "" }
        } else {
            let colon = authority.firstIndex(of: ":")
            guard let name = decodeRegName(authority[..<(colon ?? authority.endIndex)]) else { return "" }
            host = name
            port = colon.map { authority[($0 + 1)...] } ?? []
        }
        if !port.isEmpty, !isPort(string(port).trimmingCharacters(in: .whitespacesAndNewlines)) { return "" }
        return host.lowercased()
    }

    /// Whether an entry saved for `site` fills on the page at `url`: the two hosts are the same, or `site`'s is
    /// a parent domain of `url`'s, so `accounts.example.com` matches `example.com` and `badexample.com` does
    /// not.
    public static func matches(url: String, site: String) -> Bool {
        let host = hostOf(url)
        let siteHost = hostOf(site)
        return !host.isEmpty && !siteHost.isEmpty && (host == siteHost || host.hasSuffix("." + siteHost))
    }

    private static let subDelims = "!$&'()*+,;=".unicodeScalars

    private static func string<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    private static func isLetter(_ c: Unicode.Scalar) -> Bool { ("a"..."z").contains(c) || ("A"..."Z").contains(c) }

    private static func isDigit(_ c: Unicode.Scalar) -> Bool { ("0"..."9").contains(c) }

    private static func isHex(_ c: Unicode.Scalar) -> Bool {
        isDigit(c) || ("a"..."f").contains(c) || ("A"..."F").contains(c)
    }

    private static func isUnreserved(_ c: Unicode.Scalar) -> Bool {
        isLetter(c) || isDigit(c) || "-._~".unicodeScalars.contains(c)
    }

    private static func isScheme(_ scheme: ArraySlice<Unicode.Scalar>) -> Bool {
        guard let first = scheme.first, isLetter(first) else { return false }
        return scheme.allSatisfy { isLetter($0) || isDigit($0) || "+-.".unicodeScalars.contains($0) }
    }

    /// What Dart's `int.tryParse` accepts: an optional sign, then decimal digits or `0x` and hex digits.
    private static func isPort(_ port: String) -> Bool {
        var digits = Array(port.unicodeScalars)[...]
        if let sign = digits.first, sign == "+" || sign == "-" { digits = digits.dropFirst() }
        if digits.starts(with: ["0", "x"]) || digits.starts(with: ["0", "X"]) {
            let hex = digits.dropFirst(2)
            return !hex.isEmpty && hex.allSatisfy(isHex)
        }
        return !digits.isEmpty && digits.allSatisfy(isDigit)
    }

    /// A registered name with escapes of unreserved characters decoded, or nil when Dart would escape it.
    private static func decodeRegName(_ name: ArraySlice<Unicode.Scalar>) -> String? {
        var out: [Unicode.Scalar] = []
        var i = name.startIndex
        while i < name.endIndex {
            let c = name[i]
            if c == "%", i + 2 < name.endIndex, isHex(name[i + 1]), isHex(name[i + 2]),
               let value = UInt8(string(name[(i + 1)...(i + 2)]), radix: 16),
               isUnreserved(Unicode.Scalar(value)) {
                out.append(Unicode.Scalar(value))
                i += 3
                continue
            }
            guard isUnreserved(c) || subDelims.contains(c) else { return nil }
            out.append(c)
            i += 1
        }
        return string(out)
    }

    private static func isIpv6(_ host: String) -> Bool {
        guard let double = host.range(of: "::") else { return ipv6Groups(host) == 8 }
        if host[double.upperBound...].contains("::") { return false }
        let left = String(host[..<double.lowerBound])
        if left.contains(".") { return false }
        guard let a = ipv6Groups(left), let b = ipv6Groups(String(host[double.upperBound...])) else { return false }
        return a + b <= 7
    }

    /// How many 16-bit groups `part` holds, a trailing dotted IPv4 counting two; nil when it is malformed.
    private static func ipv6Groups(_ part: String) -> Int? {
        if part.isEmpty { return 0 }
        let groups = part.split(separator: ":", omittingEmptySubsequences: false)
        var n = 0
        for (i, group) in groups.enumerated() {
            if i == groups.count - 1, group.contains(".") {
                let quad = group.split(separator: ".", omittingEmptySubsequences: false)
                let valid = quad.count == 4 && quad.allSatisfy { q in
                    let significant = q.drop(while: { $0 == "0" })
                    return !q.isEmpty && q.unicodeScalars.allSatisfy(isDigit)
                        && significant.count <= 3 && (Int(significant) ?? 0) <= 255
                }
                guard valid else { return nil }
                n += 2
            } else if (1...4).contains(group.unicodeScalars.count), group.unicodeScalars.allSatisfy(isHex) {
                n += 1
            } else {
                return nil
            }
        }
        return n
    }
}
