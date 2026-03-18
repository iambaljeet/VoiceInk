import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Injects transcribed text at the cursor position in any app.
/// Desktop: save clipboard → set text → simulate paste → restore clipboard
class TextInjectionService {
  /// Inject text at current cursor position
  Future<void> injectText(String text) async {
    if (text.isEmpty) return;

    // Desktop: save clipboard → set text → simulate paste → restore
    final previousClipboard = await _getClipboard();

    // Set new text to clipboard
    await Clipboard.setData(ClipboardData(text: text));

    // Small delay to ensure clipboard is set
    await Future.delayed(const Duration(milliseconds: 50));

    // Simulate Cmd+V (paste) using AppleScript on macOS
    if (Platform.isMacOS) {
      await _pasteOnMacOS();
    } else if (Platform.isWindows) {
      await _pasteOnWindows();
    }

    // Wait for paste to complete
    await Future.delayed(const Duration(milliseconds: 100));

    // Restore previous clipboard
    if (previousClipboard != null) {
      await Clipboard.setData(ClipboardData(text: previousClipboard));
    }
  }

  Future<String?> _getClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pasteOnMacOS() async {
    // Use AppleScript to simulate Cmd+V
    await Process.run('osascript', [
      '-e',
      'tell application "System Events" to keystroke "v" using command down',
    ]);
  }

  Future<void> _pasteOnWindows() async {
    // Use PowerShell to simulate Ctrl+V
    await Process.run('powershell', [
      '-Command',
      r'''
      Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class Keyboard {
          [DllImport("user32.dll")]
          public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
          public const byte VK_CONTROL = 0x11;
          public const byte VK_V = 0x56;
          public const uint KEYEVENTF_KEYUP = 0x0002;
          public static void Paste() {
            keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
            keybd_event(VK_V, 0, 0, UIntPtr.Zero);
            keybd_event(VK_V, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
          }
        }
"@
      [Keyboard]::Paste()
      ''',
    ]);
  }
}
