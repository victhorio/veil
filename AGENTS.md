# Veil

Native macOS 27 menu-bar app for Codex and Claude Code weekly subscription allowance. The current phase is UI development with sample data. No authentication, network access, credential reads, or local usage-log scanning exists yet.

## Product boundary

One compact menu-bar item shows both providers' weekly percentage remaining. Its stacked popover shows remaining allowance, next reset, and estimated reserve or overshoot at reset. Each provider owns its observation time; the footer holds refresh and sample-data status. The gear menu holds app actions. No provider tabs, costs, tokens, charts, credits, or activity history.

Use native system typography, glass, controls, and accessibility. Keep both providers in compact inset sections with aligned remaining values and reset/pace details. Use the real OpenAI and Claude marks, not substitute symbols. Pace labels omit the “Est.” prefix; tooltips explain the estimate. Sample data must remain identifiable until real providers are connected. A missing reading is not zero; expired or stale readings must not appear current.

## Ownership

- `Sources/Allowance`: provider identity, weekly observations, and pace arithmetic. Foundation only; no UI or I/O. Pace uses the observation timestamp, not the current clock, so stale data cannot improve its own forecast.
- `Sources/Veil/Usage`: the async usage-source boundary, sample responses, and observable refresh state. The store coalesces refreshes and retains last-good observations after failure.
- `Sources/Veil/Interface`: stacked SwiftUI content and provider marks. Views present state; they do not fetch usage or calculate forecasts.
- `Sources/Veil/Resources`: bundled provider artwork and its upstream license. See `Artwork.md` there for provenance.
- `Sources/Veil/Application`: AppKit lifecycle, status item, popover, and action menu.
- `Sources/Veil/Development`: debug-only scenario selection and native render capture. This is agent tooling, not a second UI implementation.
- `scripts`: local build and launch. No package manager, Xcode project, external Swift dependencies, or service is needed.
- `reports` and `research_notes`: upstream discovery, not application requirements. The product boundary above supersedes their exploratory scope.

Keep responsibilities with one owner and APIs explicit. Add a module or abstraction only when it earns a distinct responsibility. Bias against retained tests and comments; use clear types and names instead. Add a permanent test only for a meaningful public contract that needs ongoing regression protection. Validation scripts and probes belong under `.amp/in/`, not in production targets.

## Build and run

```sh
./scripts/build
./scripts/run
```

`build` produces `.build/Veil.app`, ad-hoc signed for local use. `run` launches that bundle. Neither installs the app, changes login items, nor touches another app. Use `./scripts/build release` to check the non-debug build. Format Swift with `xcrun swift-format format --in-place --recursive Sources Package.swift`.

For debug rendering, after building:

```sh
.build/Veil.app/Contents/MacOS/Veil --capture .amp/in/artifacts/standard.png --scenario standard --appearance light
```

Scenarios: `standard`, `on-pace`, `new-week`, `stale`, `unavailable`, `offline`, `expired`. The standard sample has observations aged two and seven minutes; `stale` makes only Claude three hours old. Appearance: `light` or `dark`; omitting it follows the system. `--preview` opens a standalone native review window instead of the status-item popover. Capture uses ScreenCaptureKit's current-process API to capture only Veil's popover, without requesting screen-recording access. Glass renders through the compositor; `NSView.cacheDisplay` omits its contents. Captures omit the outer window shadow. The accompanying `-menubar.png` shows the exact template artwork on white, not a desktop screenshot. Debug controls are excluded from release builds.

Capture error `SCStreamError -3811` can be a privacy denial rather than a rendering failure. Check `replayd` logs for `TCC Disallow` before changing capture code.

The status item supports click to toggle, Escape/outside-click dismissal, right-click actions, and Command-R while the popover is open. Its gear menu exposes sample scenarios in debug builds and Quit. Refresh is simulated; there is deliberately no pretend preferences window.

For in-process UI probes, SwiftUI's accessibility tree is lazy: enable the app's `AXEnhancedUserInterface` before traversing it. Give a newly created status item a run-loop turn before clicking it, and wait for native dismissal animation before asserting that a popover closed.

## Integration boundary

Future provider clients should implement `UsageSource.fetchWeeklyAllowances()`. A missing provider key means unavailable, not zero. Normalize provider data into `WeeklyAllowance` at that boundary; keep provider credentials and decoding out of views. The source must supply the real observation time and window boundaries. See the discovery report before choosing OAuth, CLI, or browser access; those choices remain open. Reading credentials does not authorize refreshing or rewriting another client's credentials.

Pace extrapolates observed consumption across the actual window duration. The first hour is too early to estimate; projections within five percentage points of full allowance are on pace. An observation is stale after 15 minutes. These are current product choices, not provider guarantees. Reset expiry hides the old percentage until a new window arrives.
