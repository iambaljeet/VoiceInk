import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Hotkey activation mode ─────────────────────────────

/// How the push-to-talk hotkey is triggered.
enum HotkeyMode {
  fnKey,       // Hold the fn key (default, easiest)
  singleKey,   // Long-press a single function key (F5, F6, …)
  combination, // Press a modifier+key combo (⌥Space, ⌃Space, …)
}

// ─── Single function-key presets ────────────────────────

/// Available single function keys for push-to-talk.
enum FunctionKeyPreset { f5, f6, f7, f8, f9, f10, f11, f12 }

extension FunctionKeyPresetX on FunctionKeyPreset {
  String get label {
    switch (this) {
      case FunctionKeyPreset.f5:  return 'F5';
      case FunctionKeyPreset.f6:  return 'F6';
      case FunctionKeyPreset.f7:  return 'F7';
      case FunctionKeyPreset.f8:  return 'F8';
      case FunctionKeyPreset.f9:  return 'F9';
      case FunctionKeyPreset.f10: return 'F10';
      case FunctionKeyPreset.f11: return 'F11';
      case FunctionKeyPreset.f12: return 'F12';
    }
  }

  String get description => 'Hold $label to dictate';

  PhysicalKeyboardKey get physicalKey {
    switch (this) {
      case FunctionKeyPreset.f5:  return PhysicalKeyboardKey.f5;
      case FunctionKeyPreset.f6:  return PhysicalKeyboardKey.f6;
      case FunctionKeyPreset.f7:  return PhysicalKeyboardKey.f7;
      case FunctionKeyPreset.f8:  return PhysicalKeyboardKey.f8;
      case FunctionKeyPreset.f9:  return PhysicalKeyboardKey.f9;
      case FunctionKeyPreset.f10: return PhysicalKeyboardKey.f10;
      case FunctionKeyPreset.f11: return PhysicalKeyboardKey.f11;
      case FunctionKeyPreset.f12: return PhysicalKeyboardKey.f12;
    }
  }

  HotKey toHotKey() => HotKey(
        key: physicalKey,
        modifiers: [],
        scope: HotKeyScope.system,
      );
}

// ─── Modifier+key combination presets ───────────────────

/// Available push-to-talk key combination presets.
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

// ─── Service ────────────────────────────────────────────

typedef VoidAsyncCallback = Future<void> Function();

/// Manages the push-to-talk shortcut key.
///
/// Supports three modes:
///  - **fnKey**: hold the fn key (default, simplest)
///  - **singleKey**: long-press a function key (F5, etc.)
///  - **combination**: hold a modifier+key combo (⌥Space, etc.)
///
/// Persists mode, function key, and combo preset to SharedPreferences.
class HotkeyService extends ChangeNotifier {
  static const _prefMode  = 'hotkey_mode';
  static const _prefFnKey = 'hotkey_fn_key';
  static const _prefCombo = 'shortcut_preset';

  static const _fnKeyChannel = MethodChannel('com.voiceink/fnkey');

  // fn key mode is macOS-only (Windows fn key is firmware-level, not OS-visible)
  HotkeyMode _mode = Platform.isMacOS ? HotkeyMode.fnKey : HotkeyMode.singleKey;
  FunctionKeyPreset _fnKey = FunctionKeyPreset.f5;
  ShortcutPreset _combo = ShortcutPreset.optionSpace;

  HotKey? _registeredHotKey;
  VoidAsyncCallback? _onKeyDown;
  VoidAsyncCallback? _onKeyUp;
  bool _isPressed = false;

  // ── Getters ──

  HotkeyMode get mode => _mode;
  FunctionKeyPreset get fnKey => _fnKey;
  ShortcutPreset get combo => _combo;
  bool get isPressed => _isPressed;

  /// Backward-compat alias for [combo].
  ShortcutPreset get preset => _combo;

  /// Human-readable label for the currently active hotkey.
  String get activeLabel {
    switch (_mode) {
      case HotkeyMode.fnKey:
        return 'fn';
      case HotkeyMode.singleKey:
        return _fnKey.label;
      case HotkeyMode.combination:
        return _combo.label;
    }
  }

  // ── Init ──

  /// Load saved preferences.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    final savedMode = prefs.getString(_prefMode);
    if (savedMode != null) {
      try { _mode = HotkeyMode.values.firstWhere((e) => e.name == savedMode); }
      catch (_) {}
    }

    final savedFn = prefs.getString(_prefFnKey);
    if (savedFn != null) {
      try { _fnKey = FunctionKeyPreset.values.firstWhere((e) => e.name == savedFn); }
      catch (_) {}
    }

    final savedCombo = prefs.getString(_prefCombo);
    if (savedCombo != null) {
      try { _combo = ShortcutPreset.values.firstWhere((e) => e.name == savedCombo); }
      catch (_) {}
    }

    notifyListeners();
  }

  // ── Setters (persist + re-register) ──

  /// Switch between fn-key, single-key, and combination mode.
  Future<void> setMode(HotkeyMode mode) async {
    if (_mode == mode) return;
    _mode = mode;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefMode, mode.name);

    if (_onKeyDown != null && _onKeyUp != null) {
      await registerPushToTalk(_onKeyDown!, _onKeyUp!);
    }
    notifyListeners();
  }

  /// Change the function key for single-key mode.
  Future<void> setFunctionKey(FunctionKeyPreset key) async {
    if (_fnKey == key) return;
    _fnKey = key;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefFnKey, key.name);

    if (_mode == HotkeyMode.singleKey && _onKeyDown != null && _onKeyUp != null) {
      await registerPushToTalk(_onKeyDown!, _onKeyUp!);
    }
    notifyListeners();
  }

  /// Change the combination preset.
  Future<void> setCombo(ShortcutPreset preset) async {
    if (_combo == preset) return;
    _combo = preset;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCombo, preset.name);

    if (_mode == HotkeyMode.combination && _onKeyDown != null && _onKeyUp != null) {
      await registerPushToTalk(_onKeyDown!, _onKeyUp!);
    }
    notifyListeners();
  }

  /// Backward-compat alias for [setCombo].
  Future<void> setPreset(ShortcutPreset preset) => setCombo(preset);

  // ── Registration ──

  /// Register the push-to-talk hotkey with keyDown/keyUp handlers.
  Future<void> registerPushToTalk(
    VoidAsyncCallback onKeyDown,
    VoidAsyncCallback onKeyUp,
  ) async {
    _onKeyDown = onKeyDown;
    _onKeyUp = onKeyUp;

    await _unregisterCurrent();

    if (_mode == HotkeyMode.fnKey && Platform.isMacOS) {
      // Use native fn-key monitoring via platform channel (macOS only)
      _fnKeyChannel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'fnKeyDown':
            _isPressed = true;
            notifyListeners();
            await onKeyDown();
            break;
          case 'fnKeyUp':
            _isPressed = false;
            notifyListeners();
            await onKeyUp();
            break;
        }
      });
      try {
        await _fnKeyChannel.invokeMethod('startMonitoring');
        debugPrint('[HotkeyService] Registered fn key push-to-talk');
      } catch (e) {
        debugPrint('[HotkeyService] Failed to start fn key monitoring: $e');
      }
    } else {
      final hotKey = _mode == HotkeyMode.singleKey
          ? _fnKey.toHotKey()
          : _combo.toHotKey();

      _registeredHotKey = hotKey;
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
        debugPrint('[HotkeyService] Registered $activeLabel push-to-talk (${_mode.name})');
      } catch (e) {
        debugPrint('[HotkeyService] Failed to register hotkey: $e');
      }
    }
  }

  /// Unregister the current push-to-talk hotkey.
  Future<void> unregister() async {
    _onKeyDown = null;
    _onKeyUp = null;
    await _unregisterCurrent();
  }

  Future<void> _unregisterCurrent() async {
    // Stop hotkey_manager registration
    if (_registeredHotKey != null) {
      try { await hotKeyManager.unregister(_registeredHotKey!); }
      catch (_) {}
      _registeredHotKey = null;
    }
    // Stop native fn-key monitoring (macOS only)
    if (Platform.isMacOS) {
      try { await _fnKeyChannel.invokeMethod('stopMonitoring'); }
      catch (_) {}
      _fnKeyChannel.setMethodCallHandler(null);
    }
  }

  @override
  void dispose() {
    _unregisterCurrent();
    super.dispose();
  }
}
