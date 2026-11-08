import Allowance
import Foundation
import Testing
import VeilUsage

@testable import VeilCLI

struct CommandTests {
  private let date = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func partialFailureKeepsTheOtherReadingAndNeverInventsZero() throws {
    let allowance = WeeklyAllowance(
      usedPercent: 37, resetsAt: date.addingTimeInterval(3 * 86_400), observedAt: date)
    let report = UsageReport(
      readings: [(.codex, .success(allowance)), (.claude, .failure(.signInRequired))], date: date)
    let entries = try providers(in: report)
    #expect(report.exitCode == 1)
    #expect(report.text().contains("63% left"))
    #expect(report.text().contains("20pp buffer"))
    #expect(report.text().contains("Run 'claude'"))
    #expect(entries[0]["provider"] as? String == "codex")
    #expect(entries[0]["remaining_percent"] as? Double == 63)
    #expect(entries[0]["observed_at"] as? String == "2027-01-15T08:00:00Z")
    #expect(entries[1]["provider"] as? String == "claude")
    #expect(entries[1]["status"] as? String == "error")
    #expect(entries[1]["remaining_percent"] == nil)
    #expect((entries[1]["error"] as? [String: Any])?["code"] as? String == "sign_in_required")
    #expect(!report.text().contains("0% left"))
  }

  @Test func expiredAndStaleReadingsAreNotReportedAsCurrent() throws {
    let allowance = WeeklyAllowance(
      usedPercent: 80, resetsAt: date.addingTimeInterval(3 * 86_400), observedAt: date)
    let current = UsageReport(readings: [(.codex, .success(allowance))], date: date)
    let pace = try #require(try providers(in: current)[0]["pace"] as? [String: Any])
    #expect(current.exitCode == 0)
    #expect(pace["status"] as? String == "deficit")
    #expect(pace["empty_at"] as? String == "2027-01-16T08:00:00Z")
    #expect(try #require(pace["reduction_percent"] as? Double) == 100 * (1 - 1.0 / 3))
    #expect(current.text().contains("Empty in 1d 0h"))
    #expect(current.text().contains("Ease off"))

    let stale = UsageReport(
      readings: current.readings, date: date.addingTimeInterval(15 * 60))
    #expect(stale.exitCode == 1)
    #expect(stale.text().contains("Out of date"))
    let staleEntry = try providers(in: stale)[0]
    #expect(staleEntry["status"] as? String == "stale")
    #expect(staleEntry["observed_at"] as? String == "2027-01-15T08:00:00Z")
    #expect(
      (staleEntry["pace"] as? [String: Any])?["reduction_percent"] as? Double
        == pace["reduction_percent"] as? Double)

    let expired = UsageReport(readings: current.readings, date: allowance.resetsAt)
    let expiredEntry = try providers(in: expired)[0]
    #expect(expired.exitCode == 1)
    #expect(expired.text().contains("Weekly reset pending"))
    #expect(!expired.text().contains("% left"))
    #expect(expiredEntry["status"] as? String == "awaiting_reset")
    #expect(expiredEntry["remaining_percent"] == nil)
    #expect(expiredEntry["used_percent"] == nil)

    let exhausted = UsageReport(
      readings: [
        (
          .codex,
          .success(
            WeeklyAllowance(
              usedPercent: 100, resetsAt: allowance.resetsAt, observedAt: date))
        )
      ], date: date)
    #expect(exhausted.exitCode == 0)
    #expect(exhausted.text().contains("0% left"))
    #expect(exhausted.text().contains("Empty now"))
  }

  @Test func commandSelectsProvidersAndRejectsAmbiguousArguments() async throws {
    let command = try Command(arguments: ["--json", "claude"])
    let report = await command.run(source: MissingLogin())
    let entries = try providers(in: report)
    #expect(command.json)
    #expect(entries.count == 1)
    #expect(entries[0]["provider"] as? String == "claude")
    #expect(try Command(arguments: []).providers == [.codex, .claude])
    #expect(try Command(arguments: ["--help"]).help)
    #expect(throws: Command.ArgumentError.self) { try Command(arguments: ["codex", "claude"]) }
    #expect(throws: Command.ArgumentError.self) { try Command(arguments: ["--wat"]) }
  }

  private func providers(in report: UsageReport) throws -> [[String: Any]] {
    let object = try JSONSerialization.jsonObject(with: Data(report.json().utf8))
    return try #require((object as? [String: Any])?["providers"] as? [[String: Any]])
  }

  private struct MissingLogin: UsageSource {
    func fetchWeeklyAllowance(for provider: Provider) async -> UsageFetch {
      UsageFetch(credentialID: nil, result: .failure(.signInRequired))
    }
  }
}
