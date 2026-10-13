// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ThinQKit",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "ThinQKit", targets: ["ThinQKit"]),
        .executable(name: "thinq", targets: ["thinq"]),
    ],
    targets: [
        .target(name: "ThinQKit"),
        .executableTarget(name: "thinq", dependencies: ["ThinQKit"]),
        .testTarget(
            name: "ThinQKitTests",
            dependencies: ["ThinQKit"],
            resources: [.copy("Fixtures")]
        ),
        // Pure CLI logic (argument parsing, output, backoff); `@testable import thinq`.
        .testTarget(name: "thinqTests", dependencies: ["thinq"]),
    ],
    swiftLanguageModes: [.v6]
)
