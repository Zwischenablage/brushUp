// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pelican",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Pelican", targets: ["Pelican"]),
    ],
    targets: [
        .executableTarget(
            name: "Pelican",
            path: "Sources/Pelican"
        ),
        .testTarget(
            name: "PelicanTests",
            dependencies: ["Pelican"],
            path: "Tests/PelicanTests"
        ),
    ]
)
