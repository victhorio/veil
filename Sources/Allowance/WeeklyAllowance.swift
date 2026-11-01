import Foundation

public enum Provider: String, CaseIterable, Hashable, Sendable {
  case codex
  case claude

  public var displayName: String {
    switch self {
    case .codex: "Codex"
    case .claude: "Claude Code"
    }
  }
}

public enum WeeklyPace: Equatable, Sendable {
  case gatheringData
  case onPace
  case reserve(percent: Int)
  case overshoot(percent: Int)
  case awaitingReset
}

public struct WeeklyAllowance: Equatable, Sendable {
  public let usedPercent: Double
  public let windowStartedAt: Date
  public let resetsAt: Date
  public let observedAt: Date

  public init(
    usedPercent: Double,
    windowStartedAt: Date,
    resetsAt: Date,
    observedAt: Date
  ) {
    self.usedPercent = usedPercent
    self.windowStartedAt = windowStartedAt
    self.resetsAt = resetsAt
    self.observedAt = observedAt
  }

  public var remainingPercent: Double { max(0, 100 - usedPercent) }

  public func pace(at date: Date) -> WeeklyPace {
    guard date < resetsAt else { return .awaitingReset }

    let observedDuration = observedAt.timeIntervalSince(windowStartedAt)
    guard observedDuration >= 3_600 else { return .gatheringData }

    let windowDuration = resetsAt.timeIntervalSince(windowStartedAt)
    let projectedRemaining = 100 - usedPercent * windowDuration / observedDuration
    let percentage = Int(projectedRemaining.rounded())

    if abs(percentage) <= 5 { return .onPace }
    if percentage > 0 { return .reserve(percent: percentage) }
    return .overshoot(percent: -percentage)
  }

  public func isStale(at date: Date) -> Bool {
    date.timeIntervalSince(observedAt) >= 15 * 60
  }
}
