import CryptoKit
import Foundation
import LocalAuthentication
import Security

struct ProviderCredentials: Sendable {
  let accessToken: String
  let accountID: String?

  var identity: String {
    SHA256.hash(data: Data("\(accessToken)\u{0}\(accountID ?? "")".utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  static func codex(root: URL) throws -> Self {
    struct Login: Decodable {
      struct Tokens: Decodable {
        let accessToken: String
        let accountId: String?
        let idToken: String?
      }
      let tokens: Tokens?
    }
    let login = try decode(Login.self, data: readFile(root.appendingPathComponent("auth.json")))
    guard let tokens = login.tokens, !tokens.accessToken.isEmpty else {
      throw UsageFailure.signInRequired
    }
    let claims = jwtClaims(tokens.accessToken)
    if let expiry = claims?["exp"] as? Double, expiry <= Date.now.timeIntervalSince1970 {
      throw UsageFailure.loginExpired
    }
    let accountClaims = [tokens.idToken.flatMap(jwtClaims), claims].map { payload in
      let auth = payload?["https://api.openai.com/auth"] as? [String: Any]
      return auth?["chatgpt_account_id"] as? String ?? payload?["chatgpt_account_id"] as? String
    }
    let accountID = ([tokens.accountId] + accountClaims)
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
    return Self(accessToken: tokens.accessToken, accountID: accountID)
  }

  static func claude(data: Data) throws -> Self {
    struct Login: Decodable {
      struct OAuth: Decodable {
        let accessToken: String
        let expiresAt: Double
        let scopes: [String]
      }
      let claudeAiOauth: OAuth?
    }
    let login = try decode(Login.self, data: data)
    guard let oauth = login.claudeAiOauth, !oauth.accessToken.isEmpty else {
      throw UsageFailure.signInRequired
    }
    guard oauth.expiresAt.isFinite,
      oauth.expiresAt / 1_000 > Date.now.timeIntervalSince1970
    else { throw UsageFailure.loginExpired }
    guard oauth.scopes.contains("user:profile") else { throw UsageFailure.signInRequired }
    return Self(accessToken: oauth.accessToken, accountID: nil)
  }

  static func readFile(_ url: URL) throws -> Data {
    do {
      return try Data(contentsOf: url)
    } catch CocoaError.fileReadNoSuchFile {
      throw UsageFailure.signInRequired
    } catch {
      throw UsageFailure.invalidCredentials
    }
  }

  private static func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    do { return try decoder.decode(type, from: data) } catch {
      throw UsageFailure.invalidCredentials
    }
  }

  private static func jwtClaims(_ token: String) -> [String: Any]? {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    guard let data = Data(base64Encoded: payload) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }
}

actor ClaudeKeychain {
  static let shared = ClaudeKeychain()

  func read(allowPrompt: Bool) throws -> Data {
    // Legacy login-keychain ACLs can ignore per-query interaction suppression.
    guard SecKeychainSetUserInteractionAllowed(allowPrompt) == errSecSuccess else {
      throw UsageFailure.credentialAccess
    }
    defer { SecKeychainSetUserInteractionAllowed(false) }

    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "Claude Code-credentials",
      kSecMatchLimit as String: kSecMatchLimitAll,
      kSecReturnPersistentRef as String: true,
    ]
    if !allowPrompt {
      let context = LAContext()
      context.interactionNotAllowed = true
      query[kSecUseAuthenticationContext as String] = context
    }
    var matches: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &matches)
    if status == errSecItemNotFound { throw UsageFailure.signInRequired }
    guard status == errSecSuccess, let references = matches as? [Data] else {
      throw UsageFailure.credentialAccess
    }
    guard references.count == 1 else { throw UsageFailure.invalidCredentials }
    query.removeValue(forKey: kSecAttrService as String)
    query.removeValue(forKey: kSecReturnPersistentRef as String)
    query[kSecValuePersistentRef as String] = references[0]
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = true
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { throw UsageFailure.credentialAccess }
    return data
  }
}
