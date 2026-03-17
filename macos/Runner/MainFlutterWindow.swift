import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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

    // Since Flutter 3.7.0 FlutterViewController defaults to a black background.
    // Setting it to clear is the actual fix for the opaque FlutterView layer.
    flutterViewController.backgroundColor = .clear

    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }

  // Re-enforce transparency after any programmatic style change
  override var styleMask: NSWindow.StyleMask {
    didSet {
      self.isOpaque = false
      self.backgroundColor = NSColor.clear
    }
  }
}
