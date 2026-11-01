import AppKit
import SwiftUI

@MainActor
final class PanelViewController: NSViewController {
  private let panel: AllowancePanel

  init(store: UsageStore, openActions: @escaping () -> Void) {
    panel = AllowancePanel(store: store, openActions: openActions)
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  override func loadView() {
    let hosting = NSHostingView(rootView: panel)
    let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: hosting.fittingSize))
    material.material = .popover
    material.blendingMode = .withinWindow
    material.state = .active
    hosting.frame = material.bounds
    hosting.autoresizingMask = [.width, .height]
    material.addSubview(hosting)
    view = material
    preferredContentSize = material.frame.size
  }
}
