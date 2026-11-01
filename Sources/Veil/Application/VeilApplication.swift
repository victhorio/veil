import AppKit

@main
@MainActor
final class VeilApplication: NSObject, NSApplicationDelegate {
  private var statusController: StatusItemController?
  #if DEBUG
    private var preview: NativePreview?
  #endif

  static func main() {
    let application = NSApplication.shared
    let delegate = VeilApplication()
    application.setActivationPolicy(.accessory)
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let store = UsageStore()
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      if let appearance = NativePreview.argument("--appearance", in: arguments) {
        NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
      }
      if arguments.contains("--preview") || arguments.contains("--capture") {
        preview = NativePreview(store: store, arguments: arguments)
        return
      }
    #endif
    statusController = StatusItemController(store: store)
    store.refresh()
  }
}
