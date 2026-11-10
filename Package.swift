// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaperReader",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PaperReader", targets: ["PaperReader"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "PaperCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "PaperReader", dependencies: ["PaperCore"],
                          resources: [.copy("Resources/Editor")]),
        .testTarget(name: "PaperCoreTests", dependencies: ["PaperCore"])
    ],
    swiftLanguageModes: [.v6]
)
