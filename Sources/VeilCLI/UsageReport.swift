import Allowance
import Foundation
import VeilUsage

struct UsageReport {
  let readings: [(Provider, Result<WeeklyAllowance, UsageFailure>)]
  let date: Date

  var exitCode: Int32 {
    readings.allSatisfy { _, result in
      guard case .success(let allowance) = result else { return false }
      return allowance.resetsAt > date && !allowance.isStale(at: date)
    } ? 0 : 1
  }

  func text() -> String {
    let width = readings.map { $0.0.displayName.count }.max() ?? 0
    return readings.map { provider, result in
      let name = provider.displayName.padding(toLength: width + 2, withPad: " ", startingAt: 0)
      switch result {
      case .failure(let failure):
        return "\(name)— \(failure.title)\n  \(Problem(failure, provider: provider).message)"
      case .success(let allowance):
        guard allowance.resetsAt > date else {
          return "\(name)—\n  Weekly reset pending · Retry shortly"
        }
        let remaining = Int(allowance.remainingPercent.rounded())
        let stale = allowance.isStale(at: date) ? " · Out of date" : ""
        let reset = "Resets in \(countdown(to: allowance.resetsAt))"
        let pace: String
        switch allowance.pace(at: date) {
        case .gatheringData: pace = "Estimating pace…"
        case .onPace: pace = "On pace"
        case .buffer(let points): pace = "\(points)pp buffer"
        case .deficit(let emptyAt, let reduction):
          let percent =
            reduction < 0.05
            ? "<0.1" : reduction.formatted(.number.precision(.fractionLength(0...1)))
          let empty = emptyAt > date ? "Empty in \(countdown(to: emptyAt))" : "Empty now"
          pace = "\(empty) · Ease off \(percent)%"
        case .awaitingReset: pace = "Awaiting new data"
        }
        return "\(name)\(remaining)% left\(stale)\n  \(reset) · \(pace)"
      }
    }.joined(separator: "\n\n")
  }

  func json() throws -> String {
    let entries = readings.map { provider, result in
      switch result {
      case .failure(let failure):
        return Entry(
          provider: provider.rawValue, status: "error", error: Problem(failure, provider: provider))
      case .success(let allowance):
        let expired = allowance.resetsAt <= date
        return Entry(
          provider: provider.rawValue,
          status: expired ? "awaiting_reset" : allowance.isStale(at: date) ? "stale" : "ok",
          remainingPercent: expired ? nil : allowance.remainingPercent,
          usedPercent: expired ? nil : allowance.usedPercent,
          resetsAt: allowance.resetsAt, observedAt: allowance.observedAt,
          pace: Pace(allowance.pace(at: date)))
      }
    }
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(["providers": entries]), as: UTF8.self)
  }

  private func countdown(to deadline: Date) -> String {
    guard deadline > date else { return "now" }
    let minutes = max(1, Int(ceil(deadline.timeIntervalSince(date) / 60)))
    let hours = minutes / 60
    if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
    if hours > 0 { return "\(hours)h \(minutes % 60)m" }
    return "\(minutes)m"
  }

  private struct Entry: Encodable {
    let provider: String
    let status: String
    var remainingPercent: Double?
    var usedPercent: Double?
    var resetsAt: Date?
    var observedAt: Date?
    var pace: Pace?
    var error: Problem?
  }

  private struct Pace: Encodable {
    let status: String
    var bufferPercentagePoints: Int?
    var emptyAt: Date?
    var reductionPercent: Double?

    init(_ pace: WeeklyPace) {
      switch pace {
      case .gatheringData: status = "gathering_data"
      case .onPace: status = "on_pace"
      case .buffer(let points):
        status = "buffer"
        bufferPercentagePoints = points
      case .deficit(let empty, let reduction):
        status = "deficit"
        emptyAt = empty
        reductionPercent = reduction
      case .awaitingReset: status = "awaiting_reset"
      }
    }
  }

  private struct Problem: Encodable {
    let code: String
    let message: String
    var retryAt: Date?

    init(_ failure: UsageFailure, provider: Provider) {
      let command = provider.rawValue
      switch failure {
      case .signInRequired:
        code = "sign_in_required"
        message = "Run '\(command)' to sign in, then retry."
      case .loginExpired:
        code = "login_expired"
        message = "Run '\(command)' to renew its login, then retry."
      case .credentialAccess:
        code = "credential_access"
        message =
          "Unlock your login keychain and allow /usr/bin/security to read the Claude Code login."
      case .invalidCredentials:
        code = "invalid_credentials"
        message = "Check your \(command) configuration directory and subscription login."
      case .noWeeklyAllowance:
        code = "no_weekly_allowance"
        message = "No account-wide seven-day allowance was reported."
      case .invalidResponse:
        code = "invalid_response"
        message = "The provider returned an unrecognized weekly allowance. Try again later."
      case .offline:
        code = "offline"
        message = "Check your connection, then retry."
      case .serviceUnavailable:
        code = "service_unavailable"
        message = "The provider could not complete the request. Try again later."
      case .rateLimited(let until):
        code = "rate_limited"
        retryAt = until
        message = "Retry after \(until.formatted(date: .abbreviated, time: .shortened))."
      }
    }
  }
}
