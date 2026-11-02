# Veil

Native macOS 27 menu-bar app for Codex and Claude Code weekly subscription allowance. Normal launches use existing CLI logins; samples are debug-only.

## Product boundary

One compact menu-bar item shows both weekly percentages remaining. The tabless popover stacks both providers, showing remaining allowance and reset. Surplus shows current budget headroom in percentage points, not projected leftovers. Deficit shows “Resets in”, “Empty in”, and “Ease off”: both exhaustion timing and the reduction from observed average consumption must be visible without hovering.

Use native typography, glass, controls, and accessibility, with the actual provider marks and compact inset cards. Pace labels omit “Est.”; tooltips explain the baseline. Keep sample data identifiable. Missing readings are not zero; expired readings become dashes. Stale or failed readings dim in both surfaces and retain their original observation times. Pace uses accumulated consumption since the window began, not measured current workload; stale data must not improve its own forecast as the clock advances.

No extra providers, provider tabs, costs, tokens, charts, credits, activity history, or preferences window. The footer holds refresh; the gear menu holds app actions.

## Ownership

- `Sources/Allowance`: Foundation-only domain and pace arithmetic; no UI or I/O.
- `Sources/Veil/Usage`: credentials, transport, decoding, and observable provider state. The store owns scheduling and retained readings; the source owns HTTP cooldowns.
- `Sources/Veil/Application` and `Interface`: AppKit lifecycle and SwiftUI presentation. Views do not fetch usage or calculate forecasts.
- `Sources/Veil/Development`: debug-only tooling that exercises the real UI, not a parallel implementation.
- `Sources/Veil/Resources/Artwork.md`: artwork provenance and bundled license.
- `reports` and `research_notes`: historical discovery, not the current specification.

Bias against retained tests and comments; prefer clear types and names. Keep a permanent test only for a meaningful public contract needing ongoing regression protection. Temporary validation belongs under `.amp/in/`; review artifacts belong under `.amp/in/artifacts/`.

## Integration boundaries

Credentials are read-only. No renewal, credential writes, browser access, subprocess fallbacks, or usage-log scanning. Use only overall weekly subscription quotas; do not substitute session or model-specific limits. The private endpoints and CLI credential stores are compatibility surfaces, not stable public APIs.

Custom directory overrides must be absolute. Finder-launched apps do not inherit shell-only environment variables. Do not guess custom-profile Keychain services or fall back to the default profile's item when a custom profile is missing.

Keychain reads stay off MainActor. Per-query suppression alone can still open or hang on legacy login-keychain ACL prompts; the serialized reader intentionally uses the deprecated process-wide no-interaction switch. Only the explicit gear-menu action permits a prompt. Claude Code can replace its item, and ad-hoc rebuilds change Veil's identity, so access may need granting again.

Keep provider refreshes independent and respect `Retry-After`, including manual refreshes and debug source switches. Manual checks still inspect credentials during cooldown, without making HTTP requests. Failed checks must not make a retained reading look newly observed or carry it across a detected login change. Login changes are detected on checks, not through filesystem watching; in-flight results belong to the credentials read at request start.

Use ephemeral HTTP without shared cookies, response cache, or credential storage; reject redirects. Never log credentials, response bodies, account identifiers, or credential fingerprints.

## Build and run

```sh
./scripts/build
./scripts/run
./scripts/build release
xcrun swift-format format --in-place --recursive Sources Package.swift
xcrun swift-format lint --strict --recursive Sources Package.swift
```

`build` produces `.build/Veil.app`, ad-hoc signed for local use; `run` builds and launches it. Neither installs the app nor changes login items. The project uses Swift Package Manager with no external dependencies or Xcode project.

For a native debug capture, after building:

```sh
.build/Veil.app/Contents/MacOS/Veil --capture .amp/in/artifacts/standard.png --scenario standard --appearance light
```

Use `--appearance dark` for dark mode; omit it to follow the system. `--preview` opens a standalone review window. Other sample states are listed in `SampleScenario`. Adding `--live` reads actual credentials and makes provider requests; otherwise preview/capture uses samples. The accompanying `-menubar.png` is template artwork on white, not a desktop screenshot.

Capture uses ScreenCaptureKit's current-process API. Glass requires compositor capture: `NSView.cacheDisplay` omits its contents. For `SCStreamError -3811`, check `replayd` logs for `TCC Disallow` before changing rendering code. For in-process accessibility probes, enable `AXEnhancedUserInterface` before traversing SwiftUI's lazy tree. Allow native presentation/dismissal animations to finish before asserting visibility.
