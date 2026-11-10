// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaperReader",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PaperReader", targets: ["PaperReader"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "PaperCore", dependencies: ["CSQLite"], resources: [.process("Resources")]),
        .executableTarget(name: "PaperReader", dependencies: ["PaperCore", .product(name: "Sparkle", package: "Sparkle")],
                          resources: [.copy("Resources/Editor")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "PaperCoreTests", dependencies: ["PaperCore"])
    ],
    swiftLanguageModes: [.v6]
)
