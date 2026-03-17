import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionService {
  final AudioRecorder _testRecorder = AudioRecorder();
  static const _overlayChannel = MethodChannel('com.voiceink/overlay');

  bool _micGranted = false;
  bool _accessibilityGranted = false;
  int _micDenialCount = 0;

  bool get micGranted => _micGranted;
  bool get accessibilityGranted => _accessibilityGranted;
  bool get allGranted => _micGranted && _accessibilityGranted;
  /// On Android, after 2 denials the system won't show the dialog anymore
  bool get micPermanentlyDenied => Platform.isAndroid && _micDenialCount >= 2 && !_micGranted;

  Future<void> checkAll() async {
    if (Platform.isAndroid) {
      final prefs = await SharedPreferences.getInstance();
      _micDenialCount = prefs.getInt('mic_denial_count') ?? 0;
    }
    await Future.wait([checkMicrophone(), checkAccessibility()]);
  }

  Future<bool> checkMicrophone() async {
    try {
      _micGranted = await _testRecorder.hasPermission();
      if (Platform.isAndroid && !_micGranted) {
        // Increment denial count — hasPermission() on record package also requests
        _micDenialCount++;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('mic_denial_count', _micDenialCount);
      } else if (_micGranted && _micDenialCount > 0) {
        // Reset denial count if granted (e.g., user granted from settings)
        _micDenialCount = 0;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('mic_denial_count', 0);
      }
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
      if (_micGranted && _micDenialCount > 0) {
        _micDenialCount = 0;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('mic_denial_count', 0);
      }
    } catch (e) {
      debugPrint('[VoiceInk] Mic permission quiet check error: $e');
      _micGranted = false;
    }
    return _micGranted;
  }

  Future<bool> checkAccessibility() async {
    if (Platform.isAndroid) {
      try {
        _accessibilityGranted =
            await _overlayChannel.invokeMethod<bool>('checkOverlayPermission') ?? false;
      } catch (e) {
        debugPrint('[VoiceInk] Overlay permission check error: $e');
        _accessibilityGranted = false;
      }
      return _accessibilityGranted;
    }

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
    }
    if (Platform.isAndroid) {
      try {
        await _overlayChannel.invokeMethod('requestOverlayPermission');
      } catch (e) {
        debugPrint('[VoiceInk] Could not request overlay permission: $e');
      }
    }
  }

  /// Opens the app's settings page on Android (for enabling mic after permanent denial)
  Future<void> openAppSettings() async {
    if (Platform.isAndroid) {
      try {
        await _overlayChannel.invokeMethod('openAppSettings');
      } catch (e) {
        debugPrint('[VoiceInk] Could not open app settings: $e');
      }
    }
  }

  void dispose() {
    _testRecorder.dispose();
  }
}
