import Allowance
import Darwin
import Foundation

public actor LiveUsageSource: UsageSource {
  private let session: URLSession?
  private let environment: [String: String]
  private let home: URL
  private let cooldownDirectory: URL
  private var cooldowns: [Provider: Date] = [:]

  private static let defaultSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 30
    return URLSession(
      configuration: configuration, delegate: NoUsageRedirects(), delegateQueue: nil)
  }()

  public init(
    session: URLSession? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    cooldownDirectory: URL? = nil
  ) {
    self.session = session
    self.environment = environment
    self.home = home
    self.cooldownDirectory =
      cooldownDirectory ?? home.appendingPathComponent("Library/Caches/Veil", isDirectory: true)
  }

  public func fetchWeeklyAllowance(for provider: Provider) async -> UsageFetch {
    var credentialID: String?
    do {
      try Task.checkCancellation()
      let credentials: ProviderCredentials
      switch provider {
      case .codex:
        let root = try directory("CODEX_HOME", default: home.appendingPathComponent(".codex"))
        credentials = try .codex(root: root)
      case .claude:
        let defaultRoot = home.appendingPathComponent(".claude")
        let variable =
          environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"] == nil
          ? "CLAUDE_CONFIG_DIR" : "CLAUDE_SECURESTORAGE_CONFIG_DIR"
        let root = try directory(variable, default: defaultRoot)
        let file = root.appendingPathComponent(".credentials.json")
        let data: Data
        if FileManager.default.fileExists(atPath: file.path) {
          data = try ProviderCredentials.readFile(file)
        } else {
          guard
            root.standardizedFileURL == home.appendingPathComponent(".claude").standardizedFileURL
          else {
            throw UsageFailure.signInRequired
          }
          data = try await ClaudeKeychain.shared.read()
        }
        credentials = try .claude(data: data)
      }
      try Task.checkCancellation()
      credentialID = credentials.identity
      let until = cooldown(for: provider)
      if Date.now < until {
        throw UsageFailure.rateLimited(until: until)
      }
      let url =
        provider == .codex
        ? URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        : URL(string: "https://api.anthropic.com/api/oauth/usage")!
      var request = URLRequest(
        url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
      request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue("Veil/0.1", forHTTPHeaderField: "User-Agent")
      if provider == .codex, let accountID = credentials.accountID {
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
      }
      if provider == .claude {
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      }
      let (data, response) = try await (session ?? Self.defaultSession).data(for: request)
      guard let response = response as? HTTPURLResponse else { throw UsageFailure.invalidResponse }
      switch response.statusCode {
      case 200: break
      case 401, 403: throw UsageFailure.signInRequired
      case 503 where response.value(forHTTPHeaderField: "Retry-After") != nil, 429:
        let until = recordCooldown(Self.retryDate(response, now: .now), for: provider)
        throw UsageFailure.rateLimited(until: until)
      default: throw UsageFailure.serviceUnavailable
      }
      let allowance =
        try provider == .codex
        ? WeeklyUsageDecoder.codex(data, observedAt: .now)
        : WeeklyUsageDecoder.claude(data, observedAt: .now)
      return UsageFetch(credentialID: credentialID, result: .success(allowance))
    } catch let failure as UsageFailure {
      return UsageFetch(credentialID: credentialID, result: .failure(failure))
    } catch is DecodingError {
      return UsageFetch(credentialID: credentialID, result: .failure(.invalidResponse))
    } catch {
      return UsageFetch(credentialID: credentialID, result: .failure(.offline))
    }
  }

  private func directory(_ name: String, default fallback: URL) throws -> URL {
    guard let value = environment[name], !value.isEmpty else { return fallback }
    guard value.hasPrefix("/") else { throw UsageFailure.invalidCredentials }
    return URL(fileURLWithPath: value, isDirectory: true)
  }

  private func cooldown(for provider: Provider) -> Date {
    let file = cooldownDirectory.appendingPathComponent("\(provider.rawValue)-retry-after")
    let saved = (try? String(contentsOf: file, encoding: .utf8))
      .flatMap(Double.init).flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
    return max(cooldowns[provider] ?? .distantPast, saved ?? .distantPast)
  }

  private func recordCooldown(_ requested: Date, for provider: Provider) -> Date {
    var until = max(requested, cooldown(for: provider))
    defer { cooldowns[provider] = until }
    do {
      try FileManager.default.createDirectory(
        at: cooldownDirectory, withIntermediateDirectories: true)
    } catch {
      return until
    }
    let lockFile = cooldownDirectory.appendingPathComponent("\(provider.rawValue).lock")
    let descriptor = open(lockFile.path, O_CREAT | O_WRONLY | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { return until }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { return until }
    defer { flock(descriptor, LOCK_UN) }

    until = max(until, cooldown(for: provider))
    let file = cooldownDirectory.appendingPathComponent("\(provider.rawValue)-retry-after")
    try? Data(String(until.timeIntervalSince1970).utf8).write(to: file, options: .atomic)
    return until
  }

  private static func retryDate(_ response: HTTPURLResponse, now: Date) -> Date {
    let fallback = now.addingTimeInterval(300)
    guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return fallback }
    if let seconds = Double(value), seconds.isFinite {
      return max(fallback, now.addingTimeInterval(max(0, seconds)))
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
    return max(fallback, formatter.date(from: value) ?? fallback)
  }
}

private final class NoUsageRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
