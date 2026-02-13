// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProtoPost",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.1"),
    ],
    targets: [
        .executableTarget(
            name: "ProtoPost",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources"
        )
    ]
)
