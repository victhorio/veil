import Allowance
import Foundation

protocol UsageSource: Sendable {
  func fetchWeeklyAllowances() async throws -> [Provider: WeeklyAllowance]
}

enum SampleScenario: String, CaseIterable {
  case standard
  case onPace = "on-pace"
  case newWeek = "new-week"
  case stale
  case unavailable
  case offline
  case expired

  var displayName: String {
    switch self {
    case .standard: "Reserve & overshoot"
    case .onPace: "On pace"
    case .newWeek: "Just reset"
    case .stale: "One stale provider"
    case .unavailable: "One provider unavailable"
    case .offline: "Refresh failed"
    case .expired: "Awaiting weekly reset"
    }
  }
}

struct SampleUsageSource: UsageSource {
  let scenario: SampleScenario

  init(scenario: SampleScenario = .standard) {
    self.scenario = scenario
  }

  func fetchWeeklyAllowances() async throws -> [Provider: WeeklyAllowance] {
    try await Task.sleep(for: .milliseconds(650))
    if scenario == .offline { throw SampleFailure.offline }
    return allowances(at: .now)
  }

  func allowances(at date: Date) -> [Provider: WeeklyAllowance] {
    if scenario == .offline { return [:] }

    let week: TimeInterval = 7 * 24 * 3_600

    return Dictionary(
      uniqueKeysWithValues: Provider.allCases.compactMap { provider in
        if scenario == .unavailable, provider == .claude { return nil }

        let age: TimeInterval = provider == .codex ? 2 * 60 : (scenario == .stale ? 10_800 : 7 * 60)
        let observation = date.addingTimeInterval(-age)
        let elapsed: TimeInterval
        let usedPercent: Double
        switch scenario {
        case .onPace:
          elapsed = provider == .codex ? week * 0.4 : week * 0.7
          usedPercent = provider == .codex ? 40 : 70
        case .newWeek:
          elapsed = 5 * 60
          usedPercent = provider == .codex ? 0.2 : 0
        case .expired:
          elapsed = week + 60
          usedPercent = 92
        default:
          elapsed = provider == .codex ? week / 2 : 101 * 3_600
          usedPercent = provider == .codex ? 34 : 72
        }

        let start = observation.addingTimeInterval(-elapsed)
        return (
          provider,
          WeeklyAllowance(
            usedPercent: usedPercent,
            windowStartedAt: start,
            resetsAt: start.addingTimeInterval(week),
            observedAt: observation
          )
        )
      })
  }

  private enum SampleFailure: Error {
    case offline
  }
}
