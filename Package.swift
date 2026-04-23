// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Flight",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.3.1"),
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "FlightCore",
            path: "Sources/FlightCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Flight",
            dependencies: [
                "FlightCore",
                .product(name: "Textual", package: "textual"),
            ],
            path: "Sources",
            exclude: ["FlightBench", "FlightCore", "FlightServer"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FlightBench",
            dependencies: ["FlightCore"],
            path: "Sources/FlightBench",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FlightServer",
            dependencies: [
                "FlightCore",
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/FlightServer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
