// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Veil",
  platforms: [.macOS("27.0")],
  products: [
    .executable(name: "VeilApp", targets: ["Veil"]),
    .executable(name: "veil", targets: ["VeilCLI"]),
  ],
  targets: [
    .target(name: "Allowance"),
    .target(name: "VeilUsage", dependencies: ["Allowance"]),
    .executableTarget(name: "VeilCLI", dependencies: ["Allowance", "VeilUsage"]),
    .executableTarget(
      name: "Veil",
      dependencies: ["Allowance", "VeilUsage"],
      resources: [.process("Resources")]
    ),
    .testTarget(name: "VeilTests", dependencies: ["VeilCLI", "VeilUsage", "Allowance"]),
  ]
)
