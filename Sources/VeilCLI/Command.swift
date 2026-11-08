import Allowance
import Foundation
import VeilUsage

struct Command {
  struct ArgumentError: Error {
    let message: String
  }

  let providers: [Provider]
  let json: Bool
  let help: Bool

  static let helpText = """
    Weekly allowance for Codex and Claude Code.

    Usage: veil [codex|claude] [--json]

      --json      Machine-readable output with ISO 8601 dates
      -h, --help  Show this help

    Reads existing CLI logins; never renews or changes them.
    Checks both providers concurrently, or just the one you name.
    Each run fetches fresh usage, unless a provider has requested a cooldown.

    Buffer is budget headroom in percentage points, not projected leftovers.
    Pace uses average consumption since the weekly window began.

    Exit status: 0 all readings current, 1 any unavailable, 2 invalid arguments.
    """

  init(arguments: [String]) throws(ArgumentError) {
    var provider: Provider?
    var json = false
    var help = false
    for argument in arguments {
      switch argument {
      case "--json": json = true
      case "--help", "-h": help = true
      case "codex", "claude":
        guard provider == nil else {
          throw ArgumentError(message: "Choose only one provider: codex or claude.")
        }
        provider = Provider(rawValue: argument)
      default:
        throw ArgumentError(message: "Unknown argument \(argument.debugDescription).")
      }
    }
    providers = provider.map { [$0] } ?? Provider.allCases
    self.json = json
    self.help = help
  }

  func run(source: any UsageSource) async -> UsageReport {
    let results = await withTaskGroup(
      of: (Provider, Result<WeeklyAllowance, UsageFailure>).self
    ) { group in
      for provider in providers {
        group.addTask {
          (provider, await source.fetchWeeklyAllowance(for: provider).result)
        }
      }
      var results: [Provider: Result<WeeklyAllowance, UsageFailure>] = [:]
      for await (provider, result) in group { results[provider] = result }
      return results
    }
    return UsageReport(
      readings: providers.compactMap { provider in results[provider].map { (provider, $0) } },
      date: .now)
  }
}
