// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Veil",
  platforms: [.macOS("27.0")],
  products: [.executable(name: "Veil", targets: ["Veil"])],
  targets: [
    .target(name: "Allowance"),
    .executableTarget(
      name: "Veil",
      dependencies: ["Allowance"],
      resources: [.process("Resources")]
    ),
  ]
)
