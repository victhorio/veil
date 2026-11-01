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
  private var displayedPercentages: [Int?] = []

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
    observation = store.$allowances.combineLatest(store.$phase).sink { [weak self] _, _ in
      self?.updateStatusTitle()
    }
    clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.updateStatusTitle() }
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
    let needsRefresh = store.allowances.values.contains {
      $0.isStale(at: .now) || $0.resetsAt <= .now
    }
    if needsRefresh { store.refresh() }
  }

  func openActions() {
    let menu = NSMenu()
    let sampleLabel = NSMenuItem(title: "Veil · Sample data", action: nil, keyEquivalent: "")
    sampleLabel.isEnabled = false
    menu.addItem(sampleLabel)
    menu.addItem(.separator())
    let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshUsage), keyEquivalent: "r")
    refresh.target = self
    menu.addItem(refresh)

    #if DEBUG
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

  #if DEBUG
    @objc private func selectScenario(_ item: NSMenuItem) {
      store.showSampleScenario(SampleScenario.allCases[item.tag])
    }
  #endif

  private func updateStatusTitle() {
    let date = Date.now
    let percentages = Provider.allCases.map {
      UsageText.remainingPercentage(store.allowances[$0], at: date)
    }
    if percentages != displayedPercentages {
      let label = HStack(spacing: 9) {
        ForEach(Array(Provider.allCases.enumerated()), id: \.element) { index, provider in
          HStack(spacing: 3) {
            ProviderMark(provider: provider, size: 13)
            Text(percentages[index].map { "\($0)%" } ?? "—")
              .font(.system(size: 11, weight: .medium))
              .monospacedDigit()
          }
        }
      }
      .foregroundStyle(.black)
      .frame(height: 18)
      let renderer = ImageRenderer(content: label)
      renderer.scale = 2
      let image = renderer.nsImage
      image?.isTemplate = true
      statusItem.button?.image = image
      displayedPercentages = percentages
    }
    let descriptions = Provider.allCases.enumerated().map { index, provider in
      guard let percentage = percentages[index] else {
        return "\(provider.displayName): unavailable"
      }
      let stale = store.allowances[provider]?.isStale(at: date) ?? false
      return
        "\(provider.displayName): \(percentage)% left this week\(stale ? " (out of date)" : "")"
    }
    let description = "Veil · Sample data\n" + descriptions.joined(separator: "\n")
    statusItem.button?.toolTip = description
    statusItem.button?.setAccessibilityLabel(description)
  }
}
