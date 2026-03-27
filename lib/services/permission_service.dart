import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class PermissionService {
  final AudioRecorder _testRecorder = AudioRecorder();

  bool _micGranted = false;
  bool _accessibilityGranted = false;

  bool get micGranted => _micGranted;
  bool get accessibilityGranted => _accessibilityGranted;
  bool get allGranted => _micGranted && _accessibilityGranted;

  Future<void> checkAll() async {
    await Future.wait([checkMicrophone(), checkAccessibility()]);
  }

  Future<bool> checkMicrophone() async {
    try {
      _micGranted = await _testRecorder.hasPermission();
    } catch (e) {
      debugPrint('[VoiceInk] Mic permission check error: $e');
      _micGranted = false;
    }
    return _micGranted;
  }

  /// Check mic without triggering a system permission dialog (just reads cached state)
  Future<bool> checkMicrophoneQuiet() async {
    try {
      _micGranted = await _testRecorder.hasPermission();
    } catch (e) {
      debugPrint('[VoiceInk] Mic permission quiet check error: $e');
      _micGranted = false;
    }
    return _micGranted;
  }

  Future<bool> checkAccessibility() async {
    if (Platform.isWindows || Platform.isLinux) {
      _accessibilityGranted = true;
      return true;
    }

    if (!Platform.isMacOS) {
      _accessibilityGranted = true;
      return true;
    }

    // macOS: check accessibility via AppleScript
    try {
      final result = await Process.run('osascript', [
        '-e',
        'tell application "System Events" to key code 63',
      ]).timeout(const Duration(seconds: 5));
      _accessibilityGranted = result.exitCode == 0;
      if (!_accessibilityGranted) {
        debugPrint('[VoiceInk] Accessibility denied: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('[VoiceInk] Accessibility check error: $e');
      _accessibilityGranted = false;
    }
    return _accessibilityGranted;
  }

  Future<void> openAccessibilitySettings() async {
    if (Platform.isMacOS) {
      await Process.run('open', [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
      ]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', 'ms-settings:easeofaccess-display']);
    }
  }

  void dispose() {
    _testRecorder.dispose();
  }
}
