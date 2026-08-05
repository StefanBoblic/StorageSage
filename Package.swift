// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StorageSage",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StorageSage", targets: ["StorageSage"])
    ],
    targets: [
        .executableTarget(
            name: "StorageSage",
            path: "Sources/StorageSage"
        )
    ],
    swiftLanguageModes: [.v5]
)
