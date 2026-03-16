import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Keep running as a menu bar / tray app
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Prevent macOS automatic termination
    ProcessInfo.processInfo.disableAutomaticTermination("VoiceInk tray app")
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // When dock icon is clicked, show the window
    if !flag, let window = sender.windows.first {
      window.makeKeyAndOrderFront(nil)
    }
    return true
  }
}
