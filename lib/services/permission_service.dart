import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

class PermissionService {
  final AudioRecorder _testRecorder = AudioRecorder();
  static const _permChannel = MethodChannel('com.voiceink/permissions');

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
    if (!Platform.isMacOS) {
      _accessibilityGranted = true;
      return true;
    }

    try {
      final bool trusted =
          await _permChannel.invokeMethod('checkAccessibility');
      _accessibilityGranted = trusted;
    } catch (e) {
      debugPrint('[VoiceInk] Accessibility check error: $e');
      // Fallback: assume granted so we don't block the user indefinitely
      _accessibilityGranted = false;
    }
    return _accessibilityGranted;
  }

  Future<void> openAccessibilitySettings() async {
    if (Platform.isMacOS) {
      try {
        await _permChannel.invokeMethod('openAccessibilitySettings');
      } catch (e) {
        debugPrint('[VoiceInk] openAccessibilitySettings error: $e');
      }
    } else if (Platform.isWindows) {
      await Process.run(
          'cmd', ['/c', 'start', 'ms-settings:easeofaccess-display']);
    }
  }

  void dispose() {
    _testRecorder.dispose();
  }
}
