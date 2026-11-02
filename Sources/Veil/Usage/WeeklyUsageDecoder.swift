import Allowance
import Foundation

enum WeeklyUsageDecoder {
  static let week: TimeInterval = 604_800

  static func codex(_ data: Data, observedAt: Date) throws -> WeeklyAllowance {
    struct Response: Decodable {
      struct Limits: Decodable {
        struct Window: Decodable {
          struct Reading: Decodable {
            let usedPercent: Double
            let resetAt: Double
          }
          let weekly: Reading?

          enum CodingKeys: CodingKey { case limitWindowSeconds }

          init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let duration = try container.decode(Int.self, forKey: .limitWindowSeconds)
            weekly = duration == Int(WeeklyUsageDecoder.week) ? try Reading(from: decoder) : nil
          }
        }
        let primaryWindow: Window?
        let secondaryWindow: Window?
      }
      let rateLimit: Limits?
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let response = try decoder.decode(Response.self, from: data)
    let windows = [
      response.rateLimit?.primaryWindow?.weekly, response.rateLimit?.secondaryWindow?.weekly,
    ]
    .compactMap { $0 }
    guard let window = windows.first else { throw UsageFailure.noWeeklyAllowance }
    guard windows.count == 1 else { throw UsageFailure.invalidResponse }
    return try allowance(
      used: window.usedPercent,
      reset: Date(timeIntervalSince1970: window.resetAt), observedAt: observedAt)
  }

  static func claude(_ data: Data, observedAt: Date) throws -> WeeklyAllowance {
    struct Response: Decodable {
      struct Window: Decodable {
        let utilization: Double
        let resetsAt: String
      }
      let sevenDay: Window?
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let response = try decoder.decode(Response.self, from: data)
    guard let window = response.sevenDay else { throw UsageFailure.noWeeklyAllowance }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let whole = ISO8601DateFormatter()
    guard let reset = fractional.date(from: window.resetsAt) ?? whole.date(from: window.resetsAt)
    else { throw UsageFailure.invalidResponse }
    return try allowance(used: window.utilization, reset: reset, observedAt: observedAt)
  }

  private static func allowance(used: Double, reset: Date, observedAt: Date) throws
    -> WeeklyAllowance
  {
    guard used.isFinite, (0...100).contains(used), reset.timeIntervalSince1970.isFinite,
      reset.timeIntervalSince(observedAt) <= week
    else { throw UsageFailure.invalidResponse }
    return WeeklyAllowance(
      usedPercent: used, windowStartedAt: reset.addingTimeInterval(-week),
      resetsAt: reset, observedAt: observedAt)
  }
}
