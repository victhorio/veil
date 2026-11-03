import Allowance
import Foundation

protocol UsageSource: Sendable {
  func fetchWeeklyAllowance(for provider: Provider) async -> UsageFetch
}

struct UsageFetch: Sendable {
  let credentialID: String?
  let result: Result<WeeklyAllowance, UsageFailure>
}

enum UsageFailure: Error, Equatable, Sendable {
  case signInRequired
  case loginExpired
  case credentialAccess
  case invalidCredentials
  case noWeeklyAllowance
  case invalidResponse
  case offline
  case serviceUnavailable
  case rateLimited(until: Date)

  var title: String {
    switch self {
    case .signInRequired: "Sign in required"
    case .loginExpired: "Login expired"
    case .credentialAccess: "Keychain access needed"
    case .invalidCredentials: "Cannot read login"
    case .noWeeklyAllowance: "No weekly limit reported"
    case .invalidResponse: "Unexpected usage response"
    case .offline: "Connection failed"
    case .serviceUnavailable: "Service unavailable"
    case .rateLimited: "Refresh paused"
    }
  }

  func detail(for provider: Provider) -> String {
    switch self {
    case .signInRequired:
      "Open \(provider.displayName) and sign in or renew its login, then refresh. Veil never refreshes another app’s credentials."
    case .loginExpired:
      "The saved \(provider.displayName) access token has expired. Open \(provider.displayName) to renew its login, then refresh Veil. Veil never renews another app’s credentials."
    case .credentialAccess:
      "Could not read the Claude Code login from Keychain. Unlock your login keychain and refresh. macOS may ask permission for /usr/bin/security to read it."
    case .invalidCredentials:
      "The \(provider.displayName) login is unreadable or unsupported. Sign in with its subscription account, then refresh."
    case .noWeeklyAllowance:
      "\(provider.displayName) did not report an account-wide seven-day allowance. Other quota windows are not substituted."
    case .invalidResponse:
      "\(provider.displayName) returned an unrecognized weekly allowance. The previous reading, if shown, has not been updated."
    case .offline, .serviceUnavailable:
      "Could not update \(provider.displayName). The previous reading, if shown, has not been updated."
    case .rateLimited(let until):
      "\(provider.displayName) requested fewer checks. Refresh resumes after \(until.formatted(date: .omitted, time: .shortened))."
    }
  }

  var preservesReading: Bool {
    switch self {
    case .signInRequired, .loginExpired, .credentialAccess, .invalidCredentials, .noWeeklyAllowance:
      false
    default: true
    }
  }
}

#if DEBUG
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

      let week: TimeInterval = 7 * 24 * 3_600

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
              windowStartedAt: start,
              resetsAt: start.addingTimeInterval(week),
              observedAt: observation
            )
          )
        })
    }

  }
#endif
