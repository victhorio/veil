import Allowance
import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
  struct ProviderState {
    var allowance: WeeklyAllowance?
    var failure: UsageFailure?
    var isRefreshing = false
    var nextRefreshAt = Date.distantPast
    var credentialID: String?
  }

  @Published private(set) var states: [Provider: ProviderState] = [:]
  @Published private(set) var isSampleData = false

  private var source: any UsageSource
  private var refreshTasks: [Provider: Task<Void, Never>] = [:]
  #if DEBUG
    private let connectedSource: any UsageSource
  #endif

  init(source: any UsageSource = LiveUsageSource()) {
    self.source = source
    #if DEBUG
      connectedSource = source
    #endif
  }

  var isRefreshing: Bool { states.values.contains(where: \.isRefreshing) }

  func refresh() {
    for provider in Provider.allCases { refresh(provider) }
  }

  func refreshIfNeeded(at date: Date = .now) {
    guard !isSampleData else { return }
    for provider in Provider.allCases
    where date >= (states[provider]?.nextRefreshAt ?? .distantPast) {
      refresh(provider)
    }
  }

  func allowClaudeKeychainAccess() { refresh(.claude, allowCredentialPrompt: true) }

  private func refresh(_ provider: Provider, allowCredentialPrompt: Bool = false) {
    guard refreshTasks[provider] == nil else { return }
    states[provider, default: ProviderState()].isRefreshing = true
    let source = source
    refreshTasks[provider] = Task {
      let fetch = await source.fetchWeeklyAllowance(
        for: provider, allowCredentialPrompt: allowCredentialPrompt)
      guard !Task.isCancelled else { return }
      var state = states[provider] ?? ProviderState()
      if fetch.credentialID != state.credentialID { state.allowance = nil }
      state.credentialID = fetch.credentialID
      state.isRefreshing = false
      state.nextRefreshAt = Date.now.addingTimeInterval(300)
      switch fetch.result {
      case .success(let allowance):
        state.allowance = allowance
        state.failure = nil
      case .failure(let failure):
        state.failure = failure
        if !failure.preservesReading { state.allowance = nil }
        if case .rateLimited(let until) = failure { state.nextRefreshAt = until }
      }
      states[provider] = state
      refreshTasks[provider] = nil
    }
  }

  #if DEBUG
    private(set) var sampleScenario: SampleScenario?

    func useConnectedAccounts() {
      cancelRefreshes()
      source = connectedSource
      sampleScenario = nil
      isSampleData = false
      states = [:]
      refresh()
    }

    func showSampleScenario(_ scenario: SampleScenario) {
      cancelRefreshes()
      sampleScenario = scenario
      isSampleData = true
      let sample = SampleUsageSource(scenario: scenario)
      source = sample
      let allowances = sample.allowances(at: .now)
      states = Dictionary(
        uniqueKeysWithValues: Provider.allCases.map { provider in
          (
            provider,
            ProviderState(
              allowance: allowances[provider],
              failure: scenario == .offline
                ? .offline : (allowances[provider] == nil ? .noWeeklyAllowance : nil),
              credentialID: "sample")
          )
        })
    }

    private func cancelRefreshes() {
      for task in refreshTasks.values { task.cancel() }
      refreshTasks = [:]
    }
  #endif
}
