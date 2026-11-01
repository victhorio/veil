import Allowance
import SwiftUI

struct AllowancePanel: View {
  @ObservedObject var store: UsageStore
  let openActions: () -> Void

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      VStack(spacing: 8) {
        ForEach(Provider.allCases, id: \.self) { provider in
          AllowanceRow(
            provider: provider,
            allowance: store.allowances[provider],
            isLoading: store.phase == .loading,
            date: context.date
          )
        }
        footer
      }
      .padding(10)
    }
    .frame(width: 304)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var footer: some View {
    HStack(spacing: 6) {
      Text(footerText)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .help("Sample data. No provider accounts are connected.")
      Spacer(minLength: 0)
      Button(action: store.refresh) {
        Group {
          if store.phase.isRefreshing {
            ProgressView().controlSize(.mini)
          } else {
            Image(systemName: "arrow.clockwise")
          }
        }
        .frame(width: 24, height: 24)
      }
      .disabled(store.phase.isRefreshing)
      .keyboardShortcut("r", modifiers: .command)
      .help("Refresh sample data (⌘R)")
      .accessibilityLabel("Refresh weekly allowances")

      Button(action: openActions) {
        Image(systemName: "gearshape")
          .frame(width: 24, height: 24)
      }
      .help("Veil options")
      .accessibilityLabel("Veil options")
    }
    .buttonStyle(.borderless)
    .font(.system(size: 12))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 4)
  }

  private var footerText: String {
    if store.phase.isRefreshing { return "Sample data · Refreshing…" }
    if store.phase == .failed { return "Sample data · Refresh failed" }
    return "Sample data"
  }
}

private struct AllowanceRow: View {
  let provider: Provider
  let allowance: WeeklyAllowance?
  let isLoading: Bool
  let date: Date
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  private var remainingPercentage: Int? {
    UsageText.remainingPercentage(allowance, at: date)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        ProviderMark(provider: provider, size: 28)
          .foregroundStyle(provider.accentColor)
          .frame(width: 32, height: 32)
          .background(provider.accentColor.opacity(0.1), in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(provider.displayName)
            .font(.system(size: 13, weight: .semibold))
          Text(freshnessText)
            .font(.system(size: 10))
            .foregroundStyle(isStale ? Color.orange : .secondary)
            .help(
              allowance.map {
                "\(provider.displayName) observed \($0.observedAt.formatted(date: .complete, time: .shortened))"
              } ?? "No observation from \(provider.displayName)."
            )
        }
        Spacer(minLength: 8)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(remainingPercentage.map { "\($0)%" } ?? "—")
            .font(.system(size: 25, weight: .semibold))
            .monospacedDigit()
            .tracking(-0.7)
          if remainingPercentage != nil {
            Text("left")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }
        }
        .opacity(isStale ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remainingAccessibilityLabel)
      }

      GeometryReader { geometry in
        Capsule().fill(provider.accentColor.opacity(0.12))
          .overlay(alignment: .leading) {
            Capsule().fill(provider.accentColor.gradient)
              .frame(width: geometry.size.width * remainingFraction)
          }
      }
      .frame(height: 5)
      .opacity(isStale ? 0.4 : 1)
      .padding(.top, 9)
      .padding(.bottom, 9)
      .accessibilityHidden(true)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: allowance?.usedPercent)

      HStack(spacing: 8) {
        Text(resetText)
          .help(
            allowance.map { "Resets \($0.resetsAt.formatted(date: .complete, time: .shortened))" }
              ?? ""
          )
        Spacer(minLength: 0)
        if let allowance {
          paceLabel
            .help(
              "\(UsageText.pace(allowance.pace(at: date))). Based on average consumption since the weekly window began, not a prediction of future activity."
            )
            .accessibilityLabel(UsageText.pace(allowance.pace(at: date)))
        }
      }
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
    }
    .lineLimit(1)
    .padding(12)
    .glassEffect(.regular.tint(provider.accentColor.opacity(0.025)), in: .rect(cornerRadius: 16))
    .accessibilityElement(children: .contain)
  }

  private var isStale: Bool { allowance?.isStale(at: date) ?? false }

  private var freshnessText: String {
    guard let allowance else { return isLoading ? "Checking…" : "No reading" }
    let age = UsageText.observationAge(allowance.observedAt, at: date)
    return isStale ? "Out of date · \(age)" : "Updated \(age)"
  }

  private var remainingFraction: Double {
    remainingPercentage != nil ? min(1, max(0, (allowance?.remainingPercent ?? 0) / 100)) : 0
  }

  private var remainingAccessibilityLabel: String {
    if let remainingPercentage {
      return
        "\(remainingPercentage) percent of weekly allowance remaining\(isStale ? ", out of date" : "")"
    }
    return "Weekly allowance unavailable"
  }

  private var resetText: String {
    if let allowance { return UsageText.resetCountdown(allowance.resetsAt, at: date) }
    return isLoading ? "Checking weekly allowance…" : "Weekly allowance unavailable"
  }

  private var paceLabel: Text {
    guard let allowance else { return Text("") }
    switch allowance.pace(at: date) {
    case .reserve(let percent):
      return Text("\(percent)% reserve").foregroundStyle(paceColor)
    case .overshoot(let percent):
      return Text("\(percent)% over").foregroundStyle(paceColor)
    case .onPace: return Text("On pace")
    case .gatheringData: return Text("Estimating pace…")
    case .awaitingReset: return Text("Awaiting new data")
    }
  }

  private var paceColor: Color {
    guard let allowance, !allowance.isStale(at: date) else { return .secondary }
    switch allowance.pace(at: date) {
    case .reserve:
      return colorScheme == .dark
        ? Color(red: 0.53, green: 0.75, blue: 0.59)
        : Color(red: 0.2, green: 0.45, blue: 0.32)
    case .overshoot:
      return colorScheme == .dark
        ? Color(red: 0.86, green: 0.66, blue: 0.36)
        : Color(red: 0.65, green: 0.38, blue: 0.08)
    default: return .secondary
    }
  }
}
