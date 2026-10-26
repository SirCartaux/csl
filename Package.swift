// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CSL",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CSL", targets: ["CSL"])
    ],
    targets: [
        // The character picker lives in its own module so its Theme / Log /
        // Pixel helpers cannot collide with CSL's. It is linked into the one
        // CSL executable and shares its menu bar icon and login item.
        .target(
            name: "CEPKit",
            path: "Sources/CEPKit",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "CSL",
            dependencies: ["CEPKit"],
            path: "Sources/CSL",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(name: "CSLTests", dependencies: ["CSL"])
    ]
)
