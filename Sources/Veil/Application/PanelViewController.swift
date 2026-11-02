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
    hosting.translatesAutoresizingMaskIntoConstraints = false
    let material = NSVisualEffectView()
    material.material = .popover
    material.blendingMode = .withinWindow
    material.state = .active
    material.addSubview(hosting)
    NSLayoutConstraint.activate([
      hosting.leadingAnchor.constraint(equalTo: material.leadingAnchor),
      hosting.trailingAnchor.constraint(equalTo: material.trailingAnchor),
      hosting.topAnchor.constraint(equalTo: material.topAnchor),
      hosting.bottomAnchor.constraint(equalTo: material.bottomAnchor),
    ])
    view = material
    preferredContentSize = material.fittingSize
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    let size = view.fittingSize
    if preferredContentSize != size { preferredContentSize = size }
  }
}
