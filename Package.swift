// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WordToMDSwift",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WordToMDSwift", targets: ["WordToMDSwift"])
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/doc-converter-swift.git", from: "0.3.0"),
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "0.5.1"),
        .package(url: "https://github.com/PsychQuant/markdown-swift.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "WordToMDSwift",
            dependencies: [
                .product(name: "DocConverterSwift", package: "doc-converter-swift"),
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
                .product(name: "MarkdownSwift", package: "markdown-swift"),
            ]
        ),
        .testTarget(
            name: "WordToMDSwiftTests",
            dependencies: ["WordToMDSwift"]
        )
    ]
)
