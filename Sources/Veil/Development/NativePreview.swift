#if DEBUG
  import AppKit
  import ScreenCaptureKit

  @MainActor
  final class NativePreview {
    private var window: NSWindow?
    private let statusController: StatusItemController

    init(store: UsageStore, arguments: [String]) {
      let scenarioName = Self.argument("--scenario", in: arguments) ?? "standard"
      let scenario = SampleScenario(rawValue: scenarioName) ?? .standard
      store.showSampleScenario(scenario)
      statusController = StatusItemController(store: store)
      statusController.popover.appearance = NSApp.appearance

      if let path = Self.argument("--capture", in: arguments) {
        Task { @MainActor in
          do {
            try await Task.sleep(for: .milliseconds(200))
            statusController.togglePopover()
            try await Task.sleep(for: .milliseconds(900))
            guard
              let window = statusController.popover.contentViewController?.view.window
            else {
              throw CaptureFailure.popoverNotVisible
            }
            try await Self.capture(window, to: path)
            if let button = statusController.statusItem.button {
              let statusPath = (path as NSString).deletingPathExtension + "-menubar.png"
              if let image = button.image { try Self.captureStatusImage(image, to: statusPath) }
              print("Status item: \(button.frame.width) × \(button.frame.height) pt")
            }
            print(
              "Captured \(scenario.rawValue): \(window.frame.width) × \(window.frame.height) pt → \(path)"
            )
            NSApp.terminate(nil)
          } catch {
            fputs("Capture failed: \(error)\n", stderr)
            exit(1)
          }
        }
      } else {
        let controller = PanelViewController(store: store) { [weak statusController] in
          statusController?.openActions()
        }
        let content = controller.view
        let reviewWindow = NSWindow(
          contentRect: content.bounds,
          styleMask: [.titled, .closable],
          backing: .buffered,
          defer: false
        )
        reviewWindow.title = "Veil · Sample data"
        reviewWindow.contentViewController = controller
        reviewWindow.center()
        reviewWindow.makeKeyAndOrderFront(nil)
        window = reviewWindow
      }
    }

    static func argument(_ name: String, in arguments: [String]) -> String? {
      guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return nil
      }
      return arguments[index + 1]
    }

    private static func capture(_ window: NSWindow, to path: String) async throws {
      let content = try await SCShareableContent.currentProcess
      guard let ownedWindow = content.windows.first(where: { $0.windowID == window.windowNumber })
      else {
        throw CaptureFailure.popoverNotVisible
      }
      let filter = SCContentFilter(desktopIndependentWindow: ownedWindow)
      let configuration = SCStreamConfiguration()
      configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
      configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
      configuration.showsCursor = false
      configuration.ignoreShadowsSingleWindow = true
      let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: configuration)
      let bitmap = NSBitmapImageRep(cgImage: image)
      guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CaptureFailure.noBitmap
      }
      try data.write(to: URL(fileURLWithPath: path))
    }

    private static func captureStatusImage(_ image: NSImage, to path: String) throws {
      let canvas = NSImage(size: NSSize(width: image.size.width + 12, height: 22))
      canvas.lockFocus()
      NSColor.white.setFill()
      NSRect(origin: .zero, size: canvas.size).fill()
      let artwork = image.copy() as! NSImage
      artwork.isTemplate = false
      artwork.draw(in: NSRect(x: 6, y: 2, width: image.size.width, height: 18))
      canvas.unlockFocus()
      guard let tiff = canvas.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
      else {
        throw CaptureFailure.noBitmap
      }
      try data.write(to: URL(fileURLWithPath: path))
    }

    private enum CaptureFailure: Error {
      case popoverNotVisible
      case noBitmap
    }
  }
#endif
