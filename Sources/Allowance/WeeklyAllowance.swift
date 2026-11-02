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
  case buffer(percentagePoints: Int)
  case deficit(emptyAt: Date, reductionPercent: Double)
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
    if usedPercent == 100 { return .deficit(emptyAt: observedAt, reductionPercent: 100) }

    let observedDuration = observedAt.timeIntervalSince(windowStartedAt)
    guard observedDuration >= 3_600 else { return .gatheringData }

    let windowDuration = resetsAt.timeIntervalSince(windowStartedAt)
    let buffer = 100 * observedDuration / windowDuration - usedPercent
    if buffer >= 0 {
      let points = Int(buffer.rounded())
      return points == 0 ? .onPace : .buffer(percentagePoints: points)
    }

    let observedRate = usedPercent / observedDuration
    let runway = remainingPercent / observedRate
    let timeUntilReset = resetsAt.timeIntervalSince(observedAt)
    return .deficit(
      emptyAt: observedAt.addingTimeInterval(runway),
      reductionPercent: 100 * (1 - runway / timeUntilReset))
  }

  public func isStale(at date: Date) -> Bool {
    date.timeIntervalSince(observedAt) >= 15 * 60
  }
}
