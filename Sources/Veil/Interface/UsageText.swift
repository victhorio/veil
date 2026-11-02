import Allowance
import Foundation

enum UsageText {
  static func remainingPercentage(_ allowance: WeeklyAllowance?, at date: Date) -> Int? {
    guard let allowance, allowance.resetsAt > date else { return nil }
    return Int(allowance.remainingPercent.rounded())
  }

  static func resetCountdown(_ reset: Date, at date: Date) -> String {
    guard reset > date else { return "Weekly reset pending" }
    return "Resets in \(countdown(to: reset, at: date))"
  }

  static func countdown(to deadline: Date, at date: Date) -> String {
    guard deadline > date else { return "Now" }
    let minutes = max(1, Int(ceil(deadline.timeIntervalSince(date) / 60)))
    let hours = minutes / 60
    let days = hours / 24
    if days > 0 { return "\(days)d \(hours % 24)h" }
    if hours > 0 { return "\(hours)h \(minutes % 60)m" }
    return "\(minutes)m"
  }

  static func reduction(_ percent: Double) -> String {
    if percent < 0.05 { return "<0.1%" }
    return "\(percent.formatted(.number.precision(.fractionLength(0...1))))%"
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
    case .buffer(let points): "\(points) percentage points below the weekly budget so far"
    case .deficit(_, let percent):
      "Reduce average consumption by \(reduction(percent)) to last until reset"
    case .awaitingReset: "Waiting for a new weekly allowance"
    }
  }
}
