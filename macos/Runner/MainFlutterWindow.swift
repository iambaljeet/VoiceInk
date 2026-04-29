import Cocoa
import FlutterMacOS
import ApplicationServices

class MainFlutterWindow: NSWindow {
  private var hoverChannel: FlutterMethodChannel?
  private var fnKeyChannel: FlutterMethodChannel?
  private var windowChannel: FlutterMethodChannel?
  private var permissionChannel: FlutterMethodChannel?
  private var isMouseInWindow = false
  private var globalMonitor: Any?
  private var localMonitor: Any?

  // Fn-key monitoring state
  private var fnFlagsGlobalMonitor: Any?
  private var fnFlagsLocalMonitor: Any?
  private var fnKeyDown = false
  private var fnMonitoringEnabled = false

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
    self.collectionBehavior = [.canJoinAllSpaces, .stationary]
    self.acceptsMouseMovedEvents = true

    // Click-through by default so transparent areas don't block clicks
    self.ignoresMouseEvents = true

    flutterViewController.backgroundColor = .clear

    RegisterGeneratedPlugins(registry: flutterViewController)

    let messenger = flutterViewController.engine.binaryMessenger

    // Hover channel — mouse position tracking for pill hit-testing
    hoverChannel = FlutterMethodChannel(
      name: "com.voiceink/hover",
      binaryMessenger: messenger
    )

    // Fn key channel — native fn-key hold monitoring
    fnKeyChannel = FlutterMethodChannel(
      name: "com.voiceink/fnkey",
      binaryMessenger: messenger
    )
    fnKeyChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startMonitoring":
        self?.startFnKeyMonitoring()
        result(nil)
      case "stopMonitoring":
        self?.stopFnKeyMonitoring()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Window control channel — click-through toggling
    windowChannel = FlutterMethodChannel(
      name: "com.voiceink/window",
      binaryMessenger: messenger
    )
    windowChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setClickThrough":
        let clickThrough = call.arguments as? Bool ?? true
        DispatchQueue.main.async {
          self?.ignoresMouseEvents = clickThrough
        }
        result(nil)
      case "setCapsuleMode":
        let capsule = call.arguments as? Bool ?? true
        DispatchQueue.main.async {
          self?.setCapsuleMode(capsule)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Permission channel — native accessibility check + open settings
    permissionChannel = FlutterMethodChannel(
      name: "com.voiceink/permissions",
      binaryMessenger: messenger
    )
    permissionChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "checkAccessibility":
        result(AXIsProcessTrusted())
      case "openAccessibilitySettings":
        let urlString: String
        if #available(macOS 13.0, *) {
          urlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        } else {
          urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        if let url = URL(string: urlString) {
          NSWorkspace.shared.open(url)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    setupMouseMonitoring()

    super.awakeFromNib()
  }

  override var canBecomeKey: Bool { true }

  // MARK: – Capsule / Settings mode switching

  private func setCapsuleMode(_ enabled: Bool) {
    if enabled {
      self.ignoresMouseEvents = true
      self.isMovableByWindowBackground = false
    } else {
      self.ignoresMouseEvents = false
      self.isMovableByWindowBackground = false
    }
  }

  // MARK: – Fn key monitoring

  private func startFnKeyMonitoring() {
    guard !fnMonitoringEnabled else { return }
    fnMonitoringEnabled = true
    fnKeyDown = false

    fnFlagsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: .flagsChanged
    ) { [weak self] event in
      self?.handleFlagsChanged(event)
    }

    fnFlagsLocalMonitor = NSEvent.addLocalMonitorForEvents(
      matching: .flagsChanged
    ) { [weak self] event in
      self?.handleFlagsChanged(event)
      return event
    }
  }

  private func stopFnKeyMonitoring() {
    fnMonitoringEnabled = false
    if let m = fnFlagsGlobalMonitor { NSEvent.removeMonitor(m); fnFlagsGlobalMonitor = nil }
    if let m = fnFlagsLocalMonitor  { NSEvent.removeMonitor(m); fnFlagsLocalMonitor = nil }
    fnKeyDown = false
  }

  private func handleFlagsChanged(_ event: NSEvent) {
    // Only handle the actual fn key (keyCode 63)
    guard event.keyCode == 63 else { return }

    // Ignore if other modifiers are held (shift, ctrl, option, command)
    let otherModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
    if !event.modifierFlags.intersection(otherModifiers).isEmpty { return }

    let fnPressed = event.modifierFlags.contains(.function)

    if fnPressed && !fnKeyDown {
      fnKeyDown = true
      DispatchQueue.main.async { [weak self] in
        self?.fnKeyChannel?.invokeMethod("fnKeyDown", arguments: nil)
      }
    } else if !fnPressed && fnKeyDown {
      fnKeyDown = false
      DispatchQueue.main.async { [weak self] in
        self?.fnKeyChannel?.invokeMethod("fnKeyUp", arguments: nil)
      }
    }
  }

  // MARK: – Mouse monitoring

  private func setupMouseMonitoring() {
    // Global monitor works even when ignoresMouseEvents = true
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
    stopFnKeyMonitoring()
  }

  // Re-enforce transparency after any programmatic style change
  override var styleMask: NSWindow.StyleMask {
    didSet {
      self.isOpaque = false
      self.backgroundColor = NSColor.clear
    }
  }
}
