import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'package:path_provider/path_provider.dart';
import 'services/model_manager.dart';
import 'services/dictation_service.dart';
import 'ui/floating_indicator.dart';
import 'ui/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await hotKeyManager.unregisterAll();

  runApp(const VoiceInkApp());
}

class VoiceInkApp extends StatelessWidget {
  const VoiceInkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoiceInk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const VoiceInkHome(),
    );
  }
}

class VoiceInkHome extends StatefulWidget {
  const VoiceInkHome({super.key});

  @override
  State<VoiceInkHome> createState() => _VoiceInkHomeState();
}

class _VoiceInkHomeState extends State<VoiceInkHome> with WindowListener {
  late ModelManager _modelManager;
  late DictationService _dictation;
  SystemTray? _systemTray;
  bool _initialized = false;
  bool _showSettings = false;
  bool _capsuleVisible = true;
  HotKey? _dictationHotKey;
  HotKey? _toggleVisibilityHotKey;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _modelManager = ModelManager();
    _dictation = DictationService(modelManager: _modelManager);
    _initAll();
  }

  Future<void> _initAll() async {
    // Set up window FIRST before any async work
    await _setupCapsuleWindow();

    try {
      await _modelManager.init();
      await _dictation.init();
      await _registerHotkeys();
    } catch (e) {
      debugPrint('[VoiceInk] Init error: $e');
    }

    // System tray last — it's least critical
    try {
      await _initSystemTray();
    } catch (e) {
      debugPrint('[VoiceInk] Tray init error (non-fatal): $e');
    }

    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _setupCapsuleWindow() async {
    await windowManager.setSize(const Size(200, 50));
    await windowManager.setMinimumSize(const Size(160, 44));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
        windowButtonVisibility: false);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setHasShadow(false);
    await windowManager.setPosition(const Offset(600, 40));
    await windowManager.show();
  }

  Future<void> _initSystemTray() async {
    // Write tray icon to a temp file from bundled asset
    final iconPath = await _extractTrayIcon();
    if (iconPath == null) {
      debugPrint('[VoiceInk] Could not create tray icon, skipping tray');
      return;
    }

    _systemTray = SystemTray();
    await _systemTray!.initSystemTray(
      title: '',
      toolTip: 'VoiceInk — Local Voice Dictation',
      iconPath: iconPath,
    );

    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: 'Start/Stop Dictation  ⌥Space',
        onClicked: (_) async {
          await _dictation.toggleRecording();
          if (mounted) setState(() {});
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Show/Hide Capsule  ⌥V',
        onClicked: (_) => _toggleCapsuleVisibility(),
      ),
      MenuItemLabel(
        label: 'Settings...',
        onClicked: (_) => _openSettings(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Quit VoiceInk',
        onClicked: (_) => exit(0),
      ),
    ]);
    await _systemTray!.setContextMenu(menu);

    _systemTray!.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        _toggleCapsuleVisibility();
      } else if (eventName == kSystemTrayEventRightClick) {
        _systemTray!.popUpContextMenu();
      }
    });
  }

  Future<String?> _extractTrayIcon() async {
    try {
      final data = await rootBundle.load('assets/tray_icon.png');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/voiceink_tray.png');
      await file.writeAsBytes(data.buffer.asUint8List());
      return file.path;
    } catch (e) {
      debugPrint('[VoiceInk] Tray icon extract error: $e');
      return null;
    }
  }

  Future<void> _registerHotkeys() async {
    // Option+Space: toggle dictation on/off
    _dictationHotKey = HotKey(
      key: PhysicalKeyboardKey.space,
      modifiers: [HotKeyModifier.alt],
      scope: HotKeyScope.system,
    );

    await hotKeyManager.register(
      _dictationHotKey!,
      keyDownHandler: (_) async {
        if (_showSettings) return;
        await _dictation.toggleRecording();
        if (mounted) setState(() {});

        // Show capsule when recording starts
        if (_dictation.state == DictationState.recording && !_capsuleVisible) {
          _setCapsuleVisible(true);
        }
      },
    );

    // Option+V: toggle capsule visibility
    _toggleVisibilityHotKey = HotKey(
      key: PhysicalKeyboardKey.keyV,
      modifiers: [HotKeyModifier.alt],
      scope: HotKeyScope.system,
    );

    await hotKeyManager.register(
      _toggleVisibilityHotKey!,
      keyDownHandler: (_) => _toggleCapsuleVisibility(),
    );
  }

  void _toggleCapsuleVisibility() {
    _setCapsuleVisible(!_capsuleVisible);
  }

  void _setCapsuleVisible(bool visible) {
    _capsuleVisible = visible;
    if (visible) {
      windowManager.show();
    } else {
      windowManager.hide();
    }
    if (mounted) setState(() {});
  }

  void _openSettings() {
    if (mounted) {
      setState(() => _showSettings = true);
    }
    windowManager.setSize(const Size(480, 680));
    windowManager.setMinimumSize(const Size(420, 500));
    windowManager.setAlwaysOnTop(false);
    windowManager.setHasShadow(true);
    windowManager.setBackgroundColor(const Color(0xFF1a1a2e));
    if (!_capsuleVisible) {
      _capsuleVisible = true;
      windowManager.show();
    }
    windowManager.focus();
  }

  void _closeSettings() {
    if (mounted) {
      setState(() => _showSettings = false);
    }
    windowManager.setSize(const Size(200, 50));
    windowManager.setMinimumSize(const Size(160, 44));
    windowManager.setAlwaysOnTop(true);
    windowManager.setHasShadow(false);
    windowManager.setBackgroundColor(Colors.transparent);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    if (_dictationHotKey != null) hotKeyManager.unregister(_dictationHotKey!);
    if (_toggleVisibilityHotKey != null) hotKeyManager.unregister(_toggleVisibilityHotKey!);
    _dictation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const SizedBox.shrink();
    }

    if (_showSettings) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: const Color(0xFF1a1a2e),
          body: Stack(
            children: [
              SettingsScreen(
                modelManager: _modelManager,
                dictationService: _dictation,
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: _closeSettings,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Pure transparent capsule
    return ListenableBuilder(
      listenable: _dictation,
      builder: (context, _) {
        return GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          onDoubleTap: _openSettings,
          child: Container(
            color: Colors.transparent,
            child: Center(
              child: _buildCapsuleContent(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCapsuleContent() {
    // When idle with no messages, show minimal dot
    if (_dictation.state == DictationState.idle &&
        _dictation.errorMessage == null) {
      return _idleCapsule();
    }

    return FloatingIndicator(
      state: _dictation.state,
      lastText: _dictation.lastTranscription,
      error: _dictation.errorMessage,
      onCancel: () async {
        await _dictation.cancelRecording();
        if (mounted) setState(() {});
      },
    );
  }

  Widget _idleCapsule() {
    final hasModel = _modelManager.downloadedModels.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: hasModel ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            hasModel ? '⌥Space to dictate' : 'Double-click for setup',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
