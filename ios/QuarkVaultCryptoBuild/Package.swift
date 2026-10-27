// swift-tools-version: 5.9
import PackageDescription

// The iOS app links this as QuarkVaultCrypto. swift-sodium 0.10.0 is pinned
// exactly: 0.11.0 keeps hash and AEAD decrypt internal to the Sodium module,
// so this package cannot call them. A change of pin is a change to how a
// vault item opens.
let package = Package(
    name: "QuarkVaultCrypto",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "QuarkVaultCrypto", targets: ["QuarkVaultCrypto"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jedisct1/swift-sodium.git", exact: "0.10.0"),
    ],
    targets: [
        .target(
            name: "QuarkVaultCrypto",
            dependencies: [.product(name: "Sodium", package: "swift-sodium")]
        ),
    ]
)
