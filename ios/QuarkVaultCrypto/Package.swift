// swift-tools-version: 5.9
// cspell:words jedisct
import PackageDescription

// The vault crypto the iOS AutoFill extension runs with no Flutter engine (#3597,
// docs/design/native-autofill-vault.md, Decision 1), on swift-sodium: libsodium, the C library
// the app's Dart links. Pinned exactly, as a change to it is a change to how the vault opens.
// `swift test` here runs it against test/fixtures/vault_vectors.json; no Xcode project needed.
let package = Package(
    name: "QuarkVaultCrypto",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "QuarkVaultCrypto", targets: ["QuarkVaultCrypto"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jedisct1/swift-sodium.git", exact: "0.11.0"),
    ],
    targets: [
        .target(
            name: "QuarkVaultCrypto",
            dependencies: [.product(name: "Sodium", package: "swift-sodium")]
        ),
        .testTarget(
            name: "QuarkVaultCryptoTests",
            dependencies: ["QuarkVaultCrypto"]
        ),
    ]
)
