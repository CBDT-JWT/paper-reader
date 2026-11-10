// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaperReader",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PaperReader", targets: ["PaperReader"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "PaperCore", dependencies: ["CSQLite"], resources: [.process("Resources")]),
        .executableTarget(name: "PaperReader", dependencies: ["PaperCore"],
                          resources: [.copy("Resources/Editor")]),
        .testTarget(name: "PaperCoreTests", dependencies: ["PaperCore"])
    ],
    swiftLanguageModes: [.v6]
)
