// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Cyclonet",
    platforms: [.iOS(.v13),
                .tvOS(.v14),
                .macOS(.v10_15)],
    products: [
        .library(
            name: "Cyclonet",
            type: .dynamic,
            targets: ["Cyclonet"]),
    ],
    dependencies: [
        .package(url: "git@github.com:davidbaraff/Debmate.git", .branch("main")),
	.package(url: "git@github.com:davidbaraff/Starscream.git",
                 .branch("4.0.4-debmods"))
    ],
    targets: [
        .target(name: "Cyclonet",
                dependencies: ["Starscream", "Debmate"],
                path: "Sources/Cyclonet")
    ]
)
