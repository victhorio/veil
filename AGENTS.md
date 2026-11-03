# Veil

Native macOS 27 menu-bar app for Codex and Claude Code weekly subscription allowance. Swift 6.2+, Swift Package Manager, no external dependencies or Xcode project. Normal launches use existing CLI logins; samples and capture tooling are debug-only.

## Repository map

- `Sources/Allowance`: Foundation-only weekly observations and pace arithmetic; no UI or I/O.
- `Sources/Veil/Usage`: credentials, transport, decoding, and provider state. The store owns scheduling and retained readings; the source owns HTTP cooldowns.
- `Sources/Veil/Application`: AppKit lifecycle, menu-bar item, popover, and actions.
- `Sources/Veil/Interface`: SwiftUI presentation and provider marks; no fetching or forecast arithmetic.
- `Sources/Veil/Development`: previews and captures using the real UI.
- `Sources/Veil/Resources/Artwork.md`: artwork provenance and bundled license.
- `reports` and `research_notes`: historical discovery, not the current specification. The README links the upstream reference implementations.

## Product semantics

- One compact menu-bar item and a tabless, stacked popover show both providers' weekly allowance, reset, and pace. Scope excludes additional providers, costs, tokens, charts, credits, activity history, and a preferences window. Use native controls and the actual provider marks.
- Buffer means current budget headroom in percentage points, not projected leftovers. Deficit shows “Resets in”, “Empty in”, and “Ease off” without hovering. Pace is based on average consumption since the weekly window began, not current workload.
- Missing readings are not zero; expired windows show dashes. Stale or failed readings retain their observation times, dim in both surfaces, and must not gain a better forecast as time passes. Samples remain visibly identified.

## Local development

```sh
./scripts/build
./scripts/run
./scripts/build release
xcrun swift-format format --in-place --recursive Sources Package.swift
xcrun swift-format lint --strict --recursive Sources Package.swift
```

Both build configurations write `.build/Veil.app`, ad-hoc signed for local use. `run` builds debug and launches that bundle. Neither script installs the app or changes login items. There is currently no test target.

For a native capture, build debug first; release builds ignore the preview/capture arguments:

```sh
./scripts/build
mkdir -p .amp/in/artifacts
.build/Veil.app/Contents/MacOS/Veil --capture .amp/in/artifacts/standard.png --scenario standard --appearance light
```

`--preview` opens a standalone window. Use `--appearance dark` for dark mode; omit it to follow the system. Scenarios are defined in `SampleScenario`. Preview/capture uses samples unless `--live` is supplied, which reads credentials and makes real requests. The accompanying `-menubar.png` is template artwork on white, not a desktop screenshot.

Glass requires compositor capture; `NSView.cacheDisplay` omits its contents. `SCStreamError -3811` can be a TCC denial; check `replayd` logs. In-process accessibility probes need `AXEnhancedUserInterface` enabled to expose SwiftUI's lazy tree, and visibility checks need to allow native animations to finish.

## Integration notes

- Provider endpoints and CLI credential stores are private compatibility surfaces. Use overall weekly subscription quotas, not session or model-specific limits.
- Credentials belong to the CLIs. Reading them does not authorize renewing or rewriting them. Never log credentials, response bodies, account identifiers, or credential fingerprints.
- Custom directory overrides are absolute. Finder-launched apps do not inherit shell-only environment variables. A missing custom-profile login must not silently select the default account.
- Keychain reads can block or prompt and belong off MainActor. Claude Code renewal can change an item's access list; ad-hoc rebuilds change Veil's code identity. A working CLI login does not establish that Veil can read the same credential.
- Provider refreshes are independent and honor `Retry-After`, including manual checks. A failed check must not make retained data look newly observed or carry it across a detected login change.

## Local conventions

Bias against retained tests and comments; prefer clear types and names. Keep a permanent test for a meaningful public contract needing regression protection. Temporary validation belongs under `.amp/in/`; review artifacts belong under `.amp/in/artifacts/`.
