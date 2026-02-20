// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProjectCleanerApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ProjectCleanerApp", targets: ["ProjectCleanerApp"])
    ],
    targets: [
        .executableTarget(
            name: "ProjectCleanerApp",
            path: "Sources/ProjectCleanerApp"
        )
    ]
)
