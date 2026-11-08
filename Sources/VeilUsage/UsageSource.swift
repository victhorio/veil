import Allowance
import Foundation

public protocol UsageSource: Sendable {
  func fetchWeeklyAllowance(for provider: Provider) async -> UsageFetch
}

public struct UsageFetch: Sendable {
  public let credentialID: String?
  public let result: Result<WeeklyAllowance, UsageFailure>

  public init(credentialID: String?, result: Result<WeeklyAllowance, UsageFailure>) {
    self.credentialID = credentialID
    self.result = result
  }
}

public enum UsageFailure: Error, Equatable, Sendable {
  case signInRequired
  case loginExpired
  case credentialAccess
  case invalidCredentials
  case noWeeklyAllowance
  case invalidResponse
  case offline
  case serviceUnavailable
  case rateLimited(until: Date)

  public var title: String {
    switch self {
    case .signInRequired: "Sign in required"
    case .loginExpired: "Login expired"
    case .credentialAccess: "Keychain access needed"
    case .invalidCredentials: "Cannot read login"
    case .noWeeklyAllowance: "No weekly limit reported"
    case .invalidResponse: "Unexpected usage response"
    case .offline: "Connection failed"
    case .serviceUnavailable: "Service unavailable"
    case .rateLimited: "Refresh paused"
    }
  }

  public func detail(for provider: Provider) -> String {
    switch self {
    case .signInRequired:
      "Open \(provider.displayName) and sign in or renew its login, then refresh. Veil never refreshes another app’s credentials."
    case .loginExpired:
      "The saved \(provider.displayName) access token has expired. Open \(provider.displayName) to renew its login, then refresh Veil. Veil never renews another app’s credentials."
    case .credentialAccess:
      "Could not read the Claude Code login from Keychain. Unlock your login keychain and refresh. macOS may ask permission for /usr/bin/security to read it."
    case .invalidCredentials:
      "The \(provider.displayName) login is unreadable or unsupported. Sign in with its subscription account, then refresh."
    case .noWeeklyAllowance:
      "\(provider.displayName) did not report an account-wide seven-day allowance. Other quota windows are not substituted."
    case .invalidResponse:
      "\(provider.displayName) returned an unrecognized weekly allowance. The previous reading, if shown, has not been updated."
    case .offline, .serviceUnavailable:
      "Could not update \(provider.displayName). The previous reading, if shown, has not been updated."
    case .rateLimited(let until):
      "\(provider.displayName) requested fewer checks. Refresh resumes after \(until.formatted(date: .omitted, time: .shortened))."
    }
  }

  public var preservesReading: Bool {
    switch self {
    case .signInRequired, .loginExpired, .credentialAccess, .invalidCredentials, .noWeeklyAllowance:
      false
    default: true
    }
  }
}
