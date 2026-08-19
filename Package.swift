// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WordToMD",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WordToMD", targets: ["WordToMD"])
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/common-converter-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", "2.0.0"..<"4.0.0"),
        .package(url: "https://github.com/PsychQuant/markdown-swift.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "WordToMD",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
                .product(name: "MarkdownSwift", package: "markdown-swift"),
            ]
        ),
        .testTarget(
            name: "WordToMDTests",
            dependencies: ["WordToMD"]
        )
    ]
)
