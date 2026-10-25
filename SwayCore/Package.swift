// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Module map: see CONTRACT.md. Every feature module depends only on SwayModels.
// Do not add cross-module dependencies without updating CONTRACT.md first.
let featureModules = [
    "CameraService",
    "PoseEstimator",
    "PoseTraces",
    "DisplayTracker",
    "SwayUI",
    "SwitchEngine",
    "FocusControl",
    "SystemIntegration",
]

// Test resources, per module. SwitchEngineTests replays the user's recorded M1 gate trace (numeric only).
let testResources: [String: [Resource]] = [
    "SwitchEngine": [.copy("Fixtures")]
]

// Builders set SWAY_MODULE=<Module> so `swift build` / `swift test` only see SwayModels plus
// that module, isolating them from sibling modules that are mid-edit. Unset = full package.
let isolatedModule = ProcessInfo.processInfo.environment["SWAY_MODULE"].flatMap { $0.isEmpty ? nil : $0 }
let activeModules = isolatedModule.map { name in featureModules.filter { $0 == name } } ?? featureModules

var targets: [Target] = [
    .target(name: "SwayModels"),
    .testTarget(name: "SwayModelsTests", dependencies: ["SwayModels"]),
]
for module in activeModules {
    targets.append(.target(name: module, dependencies: ["SwayModels"]))
    targets.append(
        .testTarget(
            name: "\(module)Tests",
            dependencies: [.target(name: module), "SwayModels"],
            resources: testResources[module]
        )
    )
}

let package = Package(
    name: "SwayCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwayCore", targets: ["SwayModels"] + activeModules)
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
