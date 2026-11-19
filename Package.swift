// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MongoEarlgrey",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MongoEarlgrey", targets: ["MongoEarlgrey"])
    ],
    targets: [
        .executableTarget(
            name: "MongoEarlgrey",
            path: "Sources/MongoEarlgrey",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("Network"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("Security"),
                .linkedLibrary("resolv")
            ]
        )
    ]
)
