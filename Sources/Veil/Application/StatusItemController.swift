import Allowance
import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  let popover = NSPopover()
  private let store: UsageStore
  private var observation: AnyCancellable?
  private var clock: Timer?
  private var displayedReadings: [StatusReading] = []
  private var isCompact = UserDefaults.standard.bool(forKey: "compactMenuBar")

  private struct StatusReading: Equatable {
    let percentage: Int?
    let isOutOfDate: Bool
  }

  init(store: UsageStore) {
    self.store = store
    super.init()

    statusItem.button?.target = self
    statusItem.button?.action = #selector(statusItemClicked)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    popover.behavior = .transient
    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    popover.contentViewController = PanelViewController(store: store) { [weak self] in
      self?.openActions()
    }
    observation = store.$states.combineLatest(store.$isSampleData)
      .receive(on: RunLoop.main)
      .sink { [weak self] _, _ in self?.updateStatusTitle() }
    clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.store.refreshIfNeeded()
        self?.updateStatusTitle()
      }
    }
    updateStatusTitle()
  }

  @objc private func statusItemClicked() {
    if NSApp.currentEvent?.type == .rightMouseUp {
      openActions()
    } else {
      togglePopover()
    }
  }

  func togglePopover() {
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    guard let button = statusItem.button else { return }
    NSApp.activate()
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
    store.refreshIfNeeded()
  }

  func openActions() {
    let menu = NSMenu()
    let sampleLabel = NSMenuItem(
      title: store.isSampleData ? "Veil · Sample data" : "Veil", action: nil, keyEquivalent: "")
    sampleLabel.isEnabled = false
    menu.addItem(sampleLabel)
    menu.addItem(.separator())
    let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshUsage), keyEquivalent: "r")
    refresh.target = self
    menu.addItem(refresh)
    let compact = NSMenuItem(
      title: "Compact Menu Bar", action: #selector(toggleCompactMenuBar), keyEquivalent: "")
    compact.target = self
    compact.state = isCompact ? .on : .off
    menu.addItem(compact)

    #if DEBUG
      if store.isSampleData {
        let connected = NSMenuItem(
          title: "Use Connected Accounts", action: #selector(useConnectedAccounts),
          keyEquivalent: "")
        connected.target = self
        menu.addItem(connected)
      }
      let previews = NSMenu()
      for (index, scenario) in SampleScenario.allCases.enumerated() {
        let item = NSMenuItem(
          title: scenario.displayName, action: #selector(selectScenario), keyEquivalent: "")
        item.target = self
        item.tag = index
        item.state = store.sampleScenario == scenario ? .on : .off
        previews.addItem(item)
      }
      let previewItem = NSMenuItem(title: "Preview state", action: nil, keyEquivalent: "")
      previewItem.submenu = previews
      menu.addItem(previewItem)
    #endif

    menu.addItem(.separator())
    let quit = NSMenuItem(
      title: "Quit Veil", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quit)
    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
  }

  @objc private func refreshUsage() { store.refresh() }

  @objc private func toggleCompactMenuBar() {
    isCompact.toggle()
    UserDefaults.standard.set(isCompact, forKey: "compactMenuBar")
    updateStatusTitle(force: true)
  }

  #if DEBUG
    @objc private func useConnectedAccounts() { store.useConnectedAccounts() }

    @objc private func selectScenario(_ item: NSMenuItem) {
      store.showSampleScenario(SampleScenario.allCases[item.tag])
    }
  #endif

  private func updateStatusTitle(force: Bool = false) {
    let date = Date.now
    let readings = Provider.allCases.map { provider in
      let state = store.states[provider]
      return StatusReading(
        percentage: UsageText.remainingPercentage(state?.allowance, at: date),
        isOutOfDate: state?.failure != nil || (state?.allowance?.isStale(at: date) ?? false))
    }
    if force || readings != displayedReadings {
      let layout =
        isCompact
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        : AnyLayout(HStackLayout(spacing: 9))
      let label = layout {
        ForEach(Array(Provider.allCases.enumerated()), id: \.element) {
          [isCompact] index, provider in
          HStack(spacing: 3) {
            ProviderMark(provider: provider, size: isCompact ? 9 : 13)
            Text(readings[index].percentage.map { "\($0)%" } ?? "—")
              .font(.system(size: isCompact ? 9 : 11, weight: .medium))
              .monospacedDigit()
              .fixedSize()
              .frame(width: isCompact ? 28 : nil, alignment: .leading)
          }
          .frame(height: isCompact ? 9 : nil)
          .opacity(readings[index].isOutOfDate ? 0.45 : 1)
        }
      }
      .foregroundStyle(.black)
      .frame(height: 18)
      let renderer = ImageRenderer(content: label)
      renderer.scale = 2
      let image = renderer.nsImage
      image?.isTemplate = true
      statusItem.button?.image = image
      displayedReadings = readings
    }
    let descriptions = Provider.allCases.enumerated().map { index, provider in
      guard let percentage = readings[index].percentage else {
        return "\(provider.displayName): \(store.states[provider]?.failure?.title ?? "unavailable")"
      }
      return
        "\(provider.displayName): \(percentage)% left this week\(readings[index].isOutOfDate ? " (out of date)" : "")"
    }
    let description =
      (store.isSampleData ? "Veil · Sample data\n" : "Veil\n")
      + descriptions.joined(separator: "\n")
    statusItem.button?.toolTip = description
    statusItem.button?.setAccessibilityLabel(description)
  }
}
