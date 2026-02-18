// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinkInJob",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LinkInJob", targets: ["LinkInJob"])
    ],
    targets: [
        .executableTarget(
            name: "LinkInJob",
            path: ".",
            exclude: [
                "scripts",
                "dist",
                ".gitignore"
            ],
            sources: [
                "App",
                "Models",
                "ViewModels",
                "Views",
                "Services"
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
