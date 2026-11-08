import Allowance
import Foundation
import Synchronization
import Testing
import VeilUsage

struct LiveUsageTests {
  @Test func cooldownSurvivesRelaunchWithoutBlockingTheOtherProvider() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let codex = root.appendingPathComponent("codex")
    let claude = root.appendingPathComponent("claude")
    let cooldowns = root.appendingPathComponent("cooldowns")
    for directory in [codex, claude] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try Data(#"{"tokens":{"access_token":"synthetic-codex"}}"#.utf8)
      .write(to: codex.appendingPathComponent("auth.json"))
    let expiry = Date.now.addingTimeInterval(86_400).timeIntervalSince1970 * 1_000
    try Data(
      """
      {"claudeAiOauth":{"accessToken":"synthetic-claude","expiresAt":\(expiry),"scopes":["user:profile"]}}
      """.utf8
    ).write(to: claude.appendingPathComponent(".credentials.json"))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UsageProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let environment = ["CODEX_HOME": codex.path, "CLAUDE_CONFIG_DIR": claude.path]
    let first = LiveUsageSource(
      session: session, environment: environment, home: root, cooldownDirectory: cooldowns)
    UsageProtocol.rateLimited.withLock { $0 = true }
    let initial = await first.fetchWeeklyAllowance(for: .codex)
    guard case .failure(.rateLimited(let until)) = initial.result else {
      Issue.record("Expected provider cooldown")
      return
    }
    #expect(until.timeIntervalSinceNow > 3_500)

    UsageProtocol.rateLimited.withLock { $0 = false }
    let relaunched = LiveUsageSource(
      session: session, environment: environment, home: root, cooldownDirectory: cooldowns)
    let blocked = await relaunched.fetchWeeklyAllowance(for: .codex)
    guard case .failure(.rateLimited(let savedUntil)) = blocked.result else {
      Issue.record("Expected the saved cooldown, not another HTTP request")
      return
    }
    #expect(abs(savedUntil.timeIntervalSince(until)) < 1)
    let independent = await relaunched.fetchWeeklyAllowance(for: .claude)
    #expect(try independent.result.get().remainingPercent == 75)

    let uncached = LiveUsageSource(
      session: session, environment: environment, home: root,
      cooldownDirectory: root.appendingPathComponent("fresh-cooldowns"))
    let current = await uncached.fetchWeeklyAllowance(for: .codex)
    #expect(try current.result.get().remainingPercent == 63)

    let missingProfile = LiveUsageSource(
      session: session,
      environment: ["CODEX_HOME": root.appendingPathComponent("missing").path],
      home: root, cooldownDirectory: cooldowns)
    let missing = await missingProfile.fetchWeeklyAllowance(for: .codex)
    #expect(missing.result == .failure(.signInRequired))
    let relativeProfile = LiveUsageSource(
      session: session, environment: ["CODEX_HOME": "relative"], home: root,
      cooldownDirectory: cooldowns)
    let relative = await relativeProfile.fetchWeeklyAllowance(for: .codex)
    #expect(relative.result == .failure(.invalidCredentials))
  }

  @Test func overlappingRequestsCannotShortenACooldown() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(#"{"tokens":{"access_token":"synthetic-codex"}}"#.utf8)
      .write(to: root.appendingPathComponent("auth.json"))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UsageProtocol.self]
    configuration.httpAdditionalHeaders = ["X-Veil-Test": "overlap"]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    defer { UsageProtocol.pending.withLock { $0 = [] } }
    let environment = ["CODEX_HOME": root.path]
    let cooldowns = root.appendingPathComponent("cooldowns")

    try await withThrowingTaskGroup(of: UsageFetch.self) { group in
      for _ in 0..<2 {
        let source = LiveUsageSource(
          session: session, environment: environment, home: root, cooldownDirectory: cooldowns)
        group.addTask { await source.fetchWeeklyAllowance(for: .codex) }
      }
      let timeout = ContinuousClock.now.advanced(by: .seconds(3))
      while UsageProtocol.pending.withLock({ $0.count }) < 2, ContinuousClock.now < timeout {
        try await Task.sleep(for: .milliseconds(1))
      }
      let requests = UsageProtocol.pending.withLock { $0 }
      guard requests.count == 2 else {
        group.cancelAll()
        Issue.record("Both requests must start before either response")
        return
      }
      requests[0](3_600)
      let first = try #require(try await group.next())
      guard case .failure(.rateLimited(let longest)) = first.result else {
        requests[1](300)
        Issue.record("Expected the first cooldown")
        return
      }
      requests[1](300)
      let second = try #require(try await group.next())
      guard case .failure(.rateLimited(let merged)) = second.result else {
        Issue.record("Expected the merged cooldown")
        return
      }
      #expect(abs(merged.timeIntervalSince(longest)) < 1)
      let relaunched = LiveUsageSource(
        session: session, environment: environment, home: root, cooldownDirectory: cooldowns)
      let saved = await relaunched.fetchWeeklyAllowance(for: .codex)
      guard case .failure(.rateLimited(let persisted)) = saved.result else {
        Issue.record("Expected the persisted cooldown")
        return
      }
      #expect(abs(persisted.timeIntervalSince(longest)) < 1)
    }
  }
}

private final class UsageProtocol: URLProtocol, @unchecked Sendable {
  static let rateLimited = Mutex(true)
  static let pending = Mutex<[@Sendable (Int) -> Void]>([])

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    if request.value(forHTTPHeaderField: "X-Veil-Test") == "overlap" {
      let respond: @Sendable (Int) -> Void = { [self] seconds in
        respondWithCooldown(seconds: seconds)
      }
      Self.pending.withLock { $0.append(respond) }
      return
    }
    let limited = Self.rateLimited.withLock { $0 } && request.url?.host == "chatgpt.com"
    let reset = Date.now.addingTimeInterval(3 * 86_400)
    let body =
      request.url?.host == "chatgpt.com"
      ? """
      {"rate_limit":{"primary_window":{"limit_window_seconds":18000},
      "secondary_window":{"limit_window_seconds":604800,"used_percent":37,"reset_at":\(reset.timeIntervalSince1970)}}}
      """
      : """
      {"seven_day":{"utilization":25,"resets_at":"\(ISO8601DateFormatter().string(from: reset))"}}
      """
    let response = HTTPURLResponse(
      url: request.url!, statusCode: limited ? 429 : 200, httpVersion: nil,
      headerFields: limited ? ["Retry-After": "3600"] : [:])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  func respondWithCooldown(seconds: Int) {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 429, httpVersion: nil,
      headerFields: ["Retry-After": String(seconds)])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
