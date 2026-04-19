// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ImageCRC",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ImageCRC", targets: ["ImageCRC"])
    ],
    dependencies: [
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode", from: "1.3.2")
    ],
    targets: [
        .executableTarget(
            name: "ImageCRC",
            dependencies: [
                .product(name: "libwebp", package: "libwebp-Xcode")
            ],
            path: ".",
            exclude: [
                "docs",
                "ImageCRC.app",
                "ImageCRC.xcodeproj",
                "project.yml",
                "Resources",
                "Scripts",
                "Tests",
                "README.md",
                "CLAUDE.md"
            ],
            sources: [
                "App",
                "Models",
                "ViewModels",
                "Services",
                "Views"
            ]
        )
    ]
)
