// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "agentpal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "agentpal", targets: ["AgentPal"]),
        .library(name: "AgentPalCore", targets: ["AgentPalCore"])
    ],
    targets: [
        .target(name: "AgentPalCore"),
        .executableTarget(
            name: "AgentPal",
            dependencies: ["AgentPalCore"],
            resources: [.copy("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "AgentPalTests",
            dependencies: ["AgentPalCore"],
            resources: [.copy("Resources")]
        )
    ]
)
