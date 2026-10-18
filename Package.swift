// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CSL",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CSL", targets: ["CSL"])
    ],
    targets: [
        .executableTarget(
            name: "CSL",
            path: "Sources/CSL",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
