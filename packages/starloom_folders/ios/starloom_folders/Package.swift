// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "starloom_folders",
    platforms: [
        .iOS("15.0"),
    ],
    products: [
        .library(name: "starloom-folders", targets: ["starloom_folders"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "starloom_folders",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Sources/starloom_folders"
        ),
    ]
)
