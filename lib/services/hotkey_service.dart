import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available push-to-talk shortcut presets.
enum ShortcutPreset {
  optionSpace,
  controlSpace,
  optionShiftSpace,
}

extension ShortcutPresetX on ShortcutPreset {
  String get label {
    final isMac = Platform.isMacOS;
    switch (this) {
      case ShortcutPreset.optionSpace:
        return isMac ? '⌥ Space' : 'Alt + Space';
      case ShortcutPreset.controlSpace:
        return isMac ? '⌃ Space' : 'Ctrl + Space';
      case ShortcutPreset.optionShiftSpace:
        return isMac ? '⌥⇧ Space' : 'Alt + Shift + Space';
    }
  }

  String get description {
    final altKey = Platform.isMacOS ? 'Option' : 'Alt';
    switch (this) {
      case ShortcutPreset.optionSpace:
        return 'Hold $altKey + Space to dictate';
      case ShortcutPreset.controlSpace:
        return 'Hold Control + Space to dictate';
      case ShortcutPreset.optionShiftSpace:
        return 'Hold $altKey + Shift + Space to dictate';
    }
  }

  PhysicalKeyboardKey get key => PhysicalKeyboardKey.space;

  List<HotKeyModifier> get modifiers {
    switch (this) {
      case ShortcutPreset.optionSpace:
        return [HotKeyModifier.alt];
      case ShortcutPreset.controlSpace:
        return [HotKeyModifier.control];
      case ShortcutPreset.optionShiftSpace:
        return [HotKeyModifier.alt, HotKeyModifier.shift];
    }
  }

  HotKey toHotKey() => HotKey(
        key: key,
        modifiers: modifiers,
        scope: HotKeyScope.system,
      );
}

typedef VoidAsyncCallback = Future<void> Function();

/// Manages the push-to-talk shortcut key.
/// - Persists the chosen preset to SharedPreferences.
/// - Registers global hotkey with keyDown (start) and keyUp (stop) handlers.
class HotkeyService extends ChangeNotifier {
  static const _prefKey = 'shortcut_preset';

  ShortcutPreset _preset = ShortcutPreset.optionSpace;
  HotKey? _registeredHotKey;

  VoidAsyncCallback? _onKeyDown;
  VoidAsyncCallback? _onKeyUp;

  // For the shortcut test UI
  bool _isPressed = false;

  ShortcutPreset get preset => _preset;
  bool get isPressed => _isPressed;

  /// Load saved preset from prefs.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null) {
      try {
        _preset = ShortcutPreset.values.firstWhere((e) => e.name == saved);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Change the active shortcut preset. Re-registers the hotkey if active.
  Future<void> setPreset(ShortcutPreset preset) async {
    if (_preset == preset) return;
    _preset = preset;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, preset.name);

    // Re-register if we have active handlers
    if (_onKeyDown != null || _onKeyUp != null) {
      await registerPushToTalk(_onKeyDown!, _onKeyUp!);
    }
    notifyListeners();
  }

  /// Register the push-to-talk hotkey with keyDown/keyUp handlers.
  Future<void> registerPushToTalk(
    VoidAsyncCallback onKeyDown,
    VoidAsyncCallback onKeyUp,
  ) async {
    _onKeyDown = onKeyDown;
    _onKeyUp = onKeyUp;

    // Unregister previous if any
    await _unregisterCurrent();

    _registeredHotKey = _preset.toHotKey();
    try {
      await hotKeyManager.register(
        _registeredHotKey!,
        keyDownHandler: (_) async {
          _isPressed = true;
          notifyListeners();
          await onKeyDown();
        },
        keyUpHandler: (_) async {
          _isPressed = false;
          notifyListeners();
          await onKeyUp();
        },
      );
      debugPrint('[HotkeyService] Registered ${_preset.label} push-to-talk');
    } catch (e) {
      debugPrint('[HotkeyService] Failed to register hotkey: $e');
    }
  }

  /// Unregister the current push-to-talk hotkey.
  Future<void> unregister() async {
    _onKeyDown = null;
    _onKeyUp = null;
    await _unregisterCurrent();
  }

  Future<void> _unregisterCurrent() async {
    if (_registeredHotKey != null) {
      try {
        await hotKeyManager.unregister(_registeredHotKey!);
      } catch (_) {}
      _registeredHotKey = null;
    }
  }

  @override
  void dispose() {
    _unregisterCurrent();
    super.dispose();
  }
}
