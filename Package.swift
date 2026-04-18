// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "img-cc",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "img-cc", targets: ["ImgCC"])
    ],
    dependencies: [
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode", from: "1.3.2")
    ],
    targets: [
        .executableTarget(
            name: "ImgCC",
            dependencies: [
                .product(name: "libwebp", package: "libwebp-Xcode")
            ],
            path: ".",
            exclude: [
                "docs",
                "img-cc.app",
                "img-cc.xcodeproj",
                "project.yml",
                "Resources",
                "Scripts",
                "Tests",
                "README.md"
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
