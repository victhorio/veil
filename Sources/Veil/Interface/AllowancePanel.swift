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
            state: store.states[provider] ?? UsageStore.ProviderState(),
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
        .help(
          store.isSampleData
            ? "Sample data. No provider accounts are connected."
            : "Each provider refreshes independently every five minutes. Its update time appears below its name."
        )
      Spacer(minLength: 0)
      Button(action: store.refresh) {
        Group {
          if store.isRefreshing {
            ProgressView().controlSize(.mini)
          } else {
            Image(systemName: "arrow.clockwise")
          }
        }
        .frame(width: 24, height: 24)
      }
      .disabled(store.isRefreshing)
      .keyboardShortcut("r", modifiers: .command)
      .help("Refresh weekly allowances (⌘R)")
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
    if store.isSampleData {
      return store.isRefreshing ? "Sample data · Refreshing…" : "Sample data"
    }
    if store.isRefreshing { return "Refreshing…" }
    return "Auto-refresh · 5 min"
  }
}

private struct AllowanceRow: View {
  let provider: Provider
  let state: UsageStore.ProviderState
  let date: Date
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  private var allowance: WeeklyAllowance? { state.allowance }
  private var isLoading: Bool { state.isRefreshing && allowance == nil }

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
              state.failure?.detail(for: provider) ?? allowance.map {
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

      paceFooter
    }
    .lineLimit(1)
    .padding(12)
    .glassEffect(.regular.tint(provider.accentColor.opacity(0.025)), in: .rect(cornerRadius: 16))
    .accessibilityElement(children: .contain)
  }

  private var isStale: Bool { state.failure != nil || (allowance?.isStale(at: date) ?? false) }

  private var freshnessText: String {
    if isLoading { return "Checking…" }
    if let failure = state.failure, allowance == nil { return failure.title }
    guard let allowance else { return isLoading ? "Checking…" : "No reading" }
    let age = UsageText.observationAge(allowance.observedAt, at: date)
    if state.failure != nil { return "Update failed · \(age)" }
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

  @ViewBuilder
  private var paceFooter: some View {
    if let allowance {
      let pace = allowance.pace(at: date)
      switch pace {
      case .deficit(let emptyAt, let reduction):
        HStack(alignment: .top, spacing: 8) {
          paceMetric("Resets in", value: UsageText.countdown(to: allowance.resetsAt, at: date))
            .help("Resets \(allowance.resetsAt.formatted(date: .complete, time: .shortened))")
          paceMetric(
            emptyAt > date ? "Empty in" : "Empty",
            value: UsageText.countdown(to: emptyAt, at: date), color: paceColor
          )
          .help("At the average consumption rate observed since the weekly window began.")
          paceMetric("Ease off", value: "↓\(UsageText.reduction(reduction))", color: paceColor)
            .accessibilityLabel(UsageText.pace(pace))
            .help("Compared with average consumption since the weekly window began.")
        }
      case .buffer(let points): compactFooter("\(points)pp buffer", color: paceColor)
      case .onPace: compactFooter("On pace")
      case .gatheringData: compactFooter("Estimating pace…")
      case .awaitingReset: compactFooter("Awaiting new data")
      }
    } else {
      compactFooter("")
    }
  }

  private func compactFooter(_ pace: String, color: Color = .secondary) -> some View {
    HStack(spacing: 8) {
      Text(resetText)
        .help(
          allowance.map { "Resets \($0.resetsAt.formatted(date: .complete, time: .shortened))" }
            ?? ""
        )
      Spacer(minLength: 0)
      if let allowance {
        Text(pace)
          .foregroundStyle(color)
          .help(UsageText.pace(allowance.pace(at: date)))
          .accessibilityLabel(UsageText.pace(allowance.pace(at: date)))
      }
    }
    .font(.system(size: 11))
    .foregroundStyle(.secondary)
  }

  private func paceMetric(_ title: String, value: String, color: Color = .secondary) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(color)
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private var paceColor: Color {
    guard let allowance, !isStale else { return .secondary }
    switch allowance.pace(at: date) {
    case .buffer:
      return colorScheme == .dark
        ? Color(red: 0.53, green: 0.75, blue: 0.59)
        : Color(red: 0.2, green: 0.45, blue: 0.32)
    case .deficit:
      return colorScheme == .dark
        ? Color(red: 0.86, green: 0.66, blue: 0.36)
        : Color(red: 0.65, green: 0.38, blue: 0.08)
    default: return .secondary
    }
  }
}
