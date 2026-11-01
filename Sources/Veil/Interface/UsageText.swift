import Allowance
import Foundation

enum UsageText {
  static func remainingPercentage(_ allowance: WeeklyAllowance?, at date: Date) -> Int? {
    guard let allowance, allowance.resetsAt > date else { return nil }
    return Int(allowance.remainingPercent.rounded())
  }

  static func resetCountdown(_ reset: Date, at date: Date) -> String {
    guard reset > date else { return "Weekly reset pending" }
    let minutes = max(1, Int(ceil(reset.timeIntervalSince(date) / 60)))
    let hours = minutes / 60
    let days = hours / 24
    if days > 0 { return "Resets in \(days)d \(hours % 24)h" }
    if hours > 0 { return "Resets in \(hours)h \(minutes % 60)m" }
    return "Resets in \(minutes)m"
  }

  static func observationAge(_ observation: Date, at date: Date) -> String {
    let minutes = max(0, Int(date.timeIntervalSince(observation) / 60))
    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes)m ago" }
    if minutes < 1_440 { return "\(minutes / 60)h ago" }
    return "\(minutes / 1_440)d ago"
  }

  static func pace(_ pace: WeeklyPace) -> String {
    switch pace {
    case .gatheringData: "Too early to estimate"
    case .onPace: "On pace for this week"
    case .reserve(let percent): "Est. \(percent)% reserve at reset"
    case .overshoot(let percent): "Est. \(percent)% over at reset"
    case .awaitingReset: "Waiting for a new weekly allowance"
    }
  }
}
