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

  Future<bool> checkAccessibility() async {
    if (!Platform.isMacOS) {
      _accessibilityGranted = true;
      return true;
    }
    try {
      // key code 63 = fn key (harmless no-op), requires accessibility
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
    }
  }

  void dispose() {
    _testRecorder.dispose();
  }
}
