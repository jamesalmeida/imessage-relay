// swift-tools-version: 5.9
import PackageDescription

#if os(Linux)
let coreDependencies: [Target.Dependency] = ["CSQLite"]
let testDependencies: [Target.Dependency] = ["IMessageRelayCore", "CSQLite"]
#else
let coreDependencies: [Target.Dependency] = []
let testDependencies: [Target.Dependency] = ["IMessageRelayCore"]
#endif

var targets: [Target] = [
    .target(
        name: "IMessageRelayCore",
        dependencies: coreDependencies
    ),
    .executableTarget(
        name: "IMessageRelay",
        dependencies: ["IMessageRelayCore"]
    ),
    .testTarget(
        name: "IMessageRelayCoreTests",
        dependencies: testDependencies,
        exclude: ["Fixtures"]
    ),
]

#if os(Linux)
targets.insert(
    .systemLibrary(
        name: "CSQLite",
        pkgConfig: "sqlite3",
        providers: [.apt(["libsqlite3-dev"])]
    ),
    at: 0
)
#endif

let package = Package(
    name: "imessage-relay",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "IMessageRelayCore",
            targets: ["IMessageRelayCore"]
        ),
        .executable(
            name: "imessage-relay",
            targets: ["IMessageRelay"]
        ),
    ],
    targets: targets
)
