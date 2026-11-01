import Allowance
import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
  enum RefreshPhase {
    case loading
    case refreshing
    case idle
    case failed

    var isRefreshing: Bool { self == .loading || self == .refreshing }
  }

  @Published private(set) var allowances: [Provider: WeeklyAllowance] = [:]
  @Published private(set) var phase = RefreshPhase.loading

  private var source: any UsageSource
  private var refreshTask: Task<Void, Never>?

  init(source: any UsageSource = SampleUsageSource()) {
    self.source = source
  }

  func refresh() {
    guard refreshTask == nil else { return }
    phase = allowances.isEmpty ? .loading : .refreshing

    refreshTask = Task {
      do {
        let observations = try await source.fetchWeeklyAllowances()
        guard !Task.isCancelled else { return }
        allowances = observations
        phase = .idle
      } catch {
        guard !Task.isCancelled else { return }
        phase = .failed
      }
      refreshTask = nil
    }
  }

  #if DEBUG
    private(set) var sampleScenario = SampleScenario.standard

    func showSampleScenario(_ scenario: SampleScenario) {
      refreshTask?.cancel()
      refreshTask = nil
      sampleScenario = scenario
      let sample = SampleUsageSource(scenario: scenario)
      source = sample
      allowances = sample.allowances(at: .now)
      phase = scenario == .offline ? .failed : .idle
    }
  #endif
}
