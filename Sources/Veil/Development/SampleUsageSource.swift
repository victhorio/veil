#if DEBUG
  import Allowance
  import Foundation
  import VeilUsage

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
      case .standard: "Buffer & deficit"
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

    func fetchWeeklyAllowance(for provider: Provider) async -> UsageFetch {
      try? await Task.sleep(for: .milliseconds(650))
      let result: Result<WeeklyAllowance, UsageFailure>
      if scenario == .offline {
        result = .failure(.offline)
      } else if let allowance = allowances(at: .now)[provider] {
        result = .success(allowance)
      } else {
        result = .failure(.noWeeklyAllowance)
      }
      return UsageFetch(credentialID: "sample", result: result)
    }

    func allowances(at date: Date) -> [Provider: WeeklyAllowance] {
      if scenario == .offline { return [:] }
      let week = WeeklyAllowance.windowDuration
      return Dictionary(
        uniqueKeysWithValues: Provider.allCases.compactMap { provider in
          if scenario == .unavailable, provider == .claude { return nil }
          let age: TimeInterval =
            provider == .codex ? 2 * 60 : (scenario == .stale ? 10_800 : 7 * 60)
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
            elapsed = (provider == .codex ? 79 : 66) * 3_600 - age
            usedPercent = provider == .codex ? 37 : 100 * elapsed / (140 * 3_600)
          }
          let start = observation.addingTimeInterval(-elapsed)
          return (
            provider,
            WeeklyAllowance(
              usedPercent: usedPercent,
              resetsAt: start.addingTimeInterval(week),
              observedAt: observation
            )
          )
        })
    }
  }
#endif
