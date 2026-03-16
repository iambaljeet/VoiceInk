import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Transparent window for floating capsule
    self.isOpaque = false
    self.backgroundColor = NSColor.clear
    self.hasShadow = false
    self.level = .floating
    self.styleMask.insert(.borderless)
    self.isMovableByWindowBackground = true
    self.collectionBehavior = [.canJoinAllSpaces, .stationary]

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
