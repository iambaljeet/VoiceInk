import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var hoverChannel: FlutterMethodChannel?
  private var isMouseInWindow = false
  private var globalMonitor: Any?
  private var localMonitor: Any?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Fully transparent, borderless floating window
    self.styleMask = [.borderless]
    self.isOpaque = false
    self.backgroundColor = NSColor.clear
    self.hasShadow = false
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.level = .floating
    self.isMovableByWindowBackground = true
    self.collectionBehavior = [.canJoinAllSpaces, .stationary]
    self.acceptsMouseMovedEvents = true

    flutterViewController.backgroundColor = .clear

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Send mouse positions to Flutter so it can hit-test against
    // the actual capsule widget bounds (not the full window frame).
    hoverChannel = FlutterMethodChannel(
      name: "com.voiceink/hover",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    setupMouseMonitoring()

    super.awakeFromNib()
  }

  override var canBecomeKey: Bool { true }

  // MARK: – Mouse monitoring

  private func setupMouseMonitoring() {
    globalMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.mouseMoved]
    ) { [weak self] _ in
      self?.checkMousePosition()
    }

    localMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.mouseMoved]
    ) { [weak self] event in
      self?.checkMousePosition()
      return event
    }
  }

  private func checkMousePosition() {
    guard self.isVisible else { return }
    let mouseLocation = NSEvent.mouseLocation
    let inWindow = self.frame.contains(mouseLocation)

    if inWindow {
      isMouseInWindow = true
      // Convert to window-local coords with Y flipped for Flutter's top-left origin
      let windowPoint = self.convertPoint(fromScreen: mouseLocation)
      let flutterY = self.frame.height - windowPoint.y
      DispatchQueue.main.async { [weak self] in
        self?.hoverChannel?.invokeMethod(
          "mouseMove",
          arguments: ["x": windowPoint.x, "y": flutterY]
        )
      }
    } else if isMouseInWindow {
      isMouseInWindow = false
      DispatchQueue.main.async { [weak self] in
        self?.hoverChannel?.invokeMethod("mouseExit", arguments: nil)
      }
    }
  }

  deinit {
    if let m = globalMonitor { NSEvent.removeMonitor(m) }
    if let m = localMonitor  { NSEvent.removeMonitor(m) }
  }

  // Re-enforce transparency after any programmatic style change
  override var styleMask: NSWindow.StyleMask {
    didSet {
      self.isOpaque = false
      self.backgroundColor = NSColor.clear
    }
  }
}
