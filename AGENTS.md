# Veil

Native macOS 27 menu-bar app for Codex and Claude Code weekly subscription allowance. Normal launches read the existing CLI logins and fetch account-wide weekly quotas. Sample data is debug-only. No credential renewal, browser access, or usage-log scanning.

## Product boundary

One compact menu-bar item shows both providers' weekly percentage remaining. Its stacked popover shows remaining allowance and next reset. Surplus gets a single buffer label in percentage points; deficit gets three columns: “Resets in”, “Empty in”, and “Ease off”. Both exhaustion timing and the required consumption reduction must be visible without hovering. Each provider owns its observation time and failure status; the footer holds refresh. The gear menu holds app actions. No provider tabs, costs, tokens, charts, credits, or activity history.

Use native system typography, glass, controls, and accessibility. Keep both providers in compact inset sections with aligned remaining values and reset/pace details. Use the real OpenAI and Claude marks, not substitute symbols. Pace labels omit the “Est.” prefix; tooltips explain the estimate. Debug samples must remain identifiable. Missing readings are not zero; expired readings become dashes, and stale or failed readings dim in both surfaces.

## Ownership

- `Sources/Allowance`: provider identity, weekly observations, and pace arithmetic. Foundation only; no UI or I/O. Pace uses the observation timestamp, not the current clock, so stale data cannot improve its own forecast.
- `Sources/Veil/Usage`: credential reads, private HTTP endpoints, weekly decoding, async source boundary, and observable per-provider state. The store owns refresh scheduling and last-good readings; the live-source actor owns HTTP cooldowns. Credential fingerprints prevent carrying readings between logins when a check detects a switch.
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

Scenarios: `standard`, `on-pace`, `new-week`, `stale`, `unavailable`, `offline`, `expired`. The standard sample has observations aged two and seven minutes; `stale` makes only Claude three hours old. Appearance: `light` or `dark`; omitting it follows the system. `--preview` opens a standalone native review window instead of the status-item popover. Add `--live` to preview/capture connected accounts instead of samples; this reads credentials and makes real requests. Capture uses ScreenCaptureKit's current-process API to capture only Veil's popover, without requesting screen-recording access. Glass renders through the compositor; `NSView.cacheDisplay` omits its contents. Captures omit the outer window shadow. The accompanying `-menubar.png` shows the exact template artwork on white, not a desktop screenshot. Debug controls are excluded from release builds.

Capture error `SCStreamError -3811` can be a privacy denial rather than a rendering failure. Check `replayd` logs for `TCC Disallow` before changing capture code. Menu-bar artwork and its safe tooltip summary are captured first, so they remain available if compositor capture fails.

The status item supports click to toggle, Escape/outside-click dismissal, right-click actions, and Command-R while the popover is open. Its gear menu exposes explicit Claude Keychain authorization when needed, sample scenarios/return to connected accounts in debug builds, and Quit. There is no preferences window.

For in-process UI probes, SwiftUI's accessibility tree is lazy: enable the app's `AXEnhancedUserInterface` before traversing it. Give a newly created status item a run-loop turn before clicking it, and wait for native dismissal animation before asserting that a popover closed.

## Integration boundary

`UsageSource.fetchWeeklyAllowance(for:allowCredentialPrompt:)` returns one provider's result with a credential fingerprint, never raw credentials. Normalize and validate external data before constructing `WeeklyAllowance`. `observedAt` is local response receipt time, not a claimed server measurement time. Both providers' weekly starts are reconstructed as reset minus seven days.

- Codex: `CODEX_HOME/auth.json`, default `~/.codex/auth.json`; subscription OAuth only. GET `https://chatgpt.com/backend-api/wham/usage` with bearer and optional account ID. Select the seven-day window by duration, not primary/secondary position. Do not substitute five-hour or model-specific quotas.
- Claude: `.credentials.json` under `CLAUDE_SECURESTORAGE_CONFIG_DIR`, otherwise `CLAUDE_CONFIG_DIR`, default `~/.claude`. An explicitly empty secure-storage variable selects the default root. Require future millisecond expiry and `user:profile`. Only the default root may fall back to the `Claude Code-credentials` Keychain item; ambiguous duplicates fail rather than guess. GET `https://api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20`; use only overall `seven_day`.
- Custom directory overrides must be absolute. Finder-launched apps do not inherit shell-only environment variables. No custom-profile Keychain guessing, API-key quotas, subprocesses, browser cookies, token copies on disk, or token refresh/write flows.
- Keychain reads run off MainActor. The serialized reader uses the legacy process-wide no-interaction switch because per-query flags alone can still hang on login-keychain ACL prompts. Only the explicit menu action permits a prompt. Claude Code can replace its Keychain item, and ad-hoc rebuilds change Veil's identity; access may need granting again. The deprecated Security calls are intentional until that legacy credential store changes.
- HTTP uses one ephemeral session with no shared cookies, credential storage, or response cache; all redirects are rejected. Never log credentials, response bodies, account identifiers, or credential fingerprints. These private endpoints are compatibility surfaces, not stable public APIs.

Refreshes run independently at launch, manually, and when due on menu opening or the existing 30-second clock (including after wake). Each provider has one in-flight request and a five-minute polling interval. A 429 honors `Retry-After` (seconds or HTTP date) with a five-minute minimum, even for manual refresh. Manual checks still read credentials during cooldown to detect logout/switching, without making HTTP requests. Transient failures retain same-credential readings with their original timestamps and visible failure state; missing/invalid authentication or missing weekly quotas clears them. Authentication changes are observed on checks, not through filesystem watching; in-flight results belong to the credentials read at request start.

Buffer is the elapsed share of the window minus used allowance, not projected leftovers. Deficit extrapolates the observed average rate to an absolute exhaustion time; “Ease off” is the reduction from that rate needed to last until reset, not a percentage of quota. The first hour is too early to estimate, unless quota is already exhausted. An observation is stale after 15 minutes. These are current product choices, not provider guarantees. Reset expiry hides the old percentage until a new window arrives.
