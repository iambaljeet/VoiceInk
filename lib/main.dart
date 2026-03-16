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
import 'services/permission_service.dart';
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
        canvasColor: Colors.transparent,
      ),
      home: const VoiceInkHome(),
    );
  }
}

enum AppMode { loading, permissions, capsule, settings }

class VoiceInkHome extends StatefulWidget {
  const VoiceInkHome({super.key});

  @override
  State<VoiceInkHome> createState() => _VoiceInkHomeState();
}

class _VoiceInkHomeState extends State<VoiceInkHome> with WindowListener {
  late ModelManager _modelManager;
  late DictationService _dictation;
  final PermissionService _permissions = PermissionService();
  SystemTray? _systemTray;

  AppMode _mode = AppMode.loading;
  bool _capsuleVisible = true;
  Timer? _permPoll;
  HotKey? _dictationHotKey;
  HotKey? _toggleHotKey;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _modelManager = ModelManager();
    _dictation = DictationService(modelManager: _modelManager);
    _boot();
  }

  Future<void> _boot() async {
    debugPrint('[VoiceInk] Checking permissions...');
    await _permissions.checkAll();
    debugPrint('[VoiceInk] mic=${_permissions.micGranted} acc=${_permissions.accessibilityGranted}');

    if (!_permissions.allGranted) {
      _mode = AppMode.permissions;
      if (mounted) setState(() {});
      await _setupPermissionWindow();
      _permPoll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _recheckPerms(),
      );
      return;
    }

    await _goLive();
  }

  Future<void> _recheckPerms() async {
    await _permissions.checkAll();
    if (mounted) setState(() {});
    if (_permissions.allGranted) {
      _permPoll?.cancel();
      _permPoll = null;
      await _goLive();
    }
  }

  Future<void> _goLive() async {
    _mode = AppMode.capsule;
    if (mounted) setState(() {});
    await _setupCapsuleWindow();

    try {
      await _modelManager.init();
      debugPrint('[VoiceInk] Models: ${_modelManager.downloadedModels.length}');
      await _dictation.init();
      await _registerHotkeys();
    } catch (e) {
      debugPrint('[VoiceInk] Init error: $e');
    }

    try {
      await _initSystemTray();
    } catch (e) {
      debugPrint('[VoiceInk] Tray error: $e');
    }

    await windowManager.setPreventClose(true);
  }

  // ───── Window configs ─────

  Future<void> _setupPermissionWindow() async {
    await windowManager.setSize(const Size(400, 360));
    await windowManager.setMinimumSize(const Size(400, 360));
    await windowManager.setMaximumSize(const Size(400, 360));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
        windowButtonVisibility: false);
    await windowManager.setBackgroundColor(const Color(0xFF1a1a2e));
    await windowManager.setHasShadow(true);
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _setupCapsuleWindow() async {
    await windowManager.setMaximumSize(const Size(800, 200));
    await windowManager.setSize(const Size(180, 50));
    await windowManager.setMinimumSize(const Size(50, 50));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
        windowButtonVisibility: false);
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setHasShadow(false);
    await windowManager.setPosition(const Offset(600, 40));
    await windowManager.show();
    await windowManager.focus();
  }

  // ───── System tray ─────

  Future<void> _initSystemTray() async {
    final iconPath = await _extractTrayIcon();
    if (iconPath == null) return;

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
          if (!_permissions.allGranted) return;
          await _dictation.toggleRecording();
          if (mounted) setState(() {});
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Show/Hide Capsule  ⌥V',
        onClicked: (_) => _toggleCapsule(),
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
      // Both click and right-click show the context menu
      if (eventName == kSystemTrayEventClick ||
          eventName == kSystemTrayEventRightClick) {
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
      debugPrint('[VoiceInk] Tray icon error: $e');
      return null;
    }
  }

  // ───── Hotkeys ─────

  Future<void> _registerHotkeys() async {
    _dictationHotKey = HotKey(
      key: PhysicalKeyboardKey.space,
      modifiers: [HotKeyModifier.alt],
      scope: HotKeyScope.system,
    );
    await hotKeyManager.register(
      _dictationHotKey!,
      keyDownHandler: (_) async {
        if (_mode == AppMode.settings || _mode == AppMode.permissions) return;
        if (!_permissions.allGranted) return;
        await _dictation.toggleRecording();
        if (mounted) setState(() {});
        if (_dictation.state == DictationState.recording && !_capsuleVisible) {
          _showCapsule();
        }
      },
    );

    _toggleHotKey = HotKey(
      key: PhysicalKeyboardKey.keyV,
      modifiers: [HotKeyModifier.alt],
      scope: HotKeyScope.system,
    );
    await hotKeyManager.register(
      _toggleHotKey!,
      keyDownHandler: (_) => _toggleCapsule(),
    );
  }

  // ───── Visibility ─────

  void _toggleCapsule() {
    _capsuleVisible ? _hideCapsule() : _showCapsule();
  }

  void _showCapsule() {
    _capsuleVisible = true;
    windowManager.show();
    if (mounted) setState(() {});
  }

  void _hideCapsule() {
    _capsuleVisible = false;
    windowManager.hide();
    if (mounted) setState(() {});
  }

  // ───── Settings ─────

  void _openSettings() async {
    _mode = AppMode.settings;
    if (mounted) setState(() {});
    await windowManager.setMaximumSize(const Size(800, 900));
    await windowManager.setMinimumSize(const Size(420, 500));
    await windowManager.setSize(const Size(480, 680));
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setHasShadow(true);
    await windowManager.setBackgroundColor(const Color(0xFF1a1a2e));
    if (!_capsuleVisible) {
      _capsuleVisible = true;
      await windowManager.show();
    }
    await windowManager.focus();
  }

  void _closeSettings() {
    _mode = AppMode.capsule;
    if (mounted) setState(() {});
    _setupCapsuleWindow();
  }

  // ───── Window listener ─────

  @override
  void onWindowClose() async {
    // Hide instead of closing — app stays alive in tray
    _hideCapsule();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _permPoll?.cancel();
    if (_dictationHotKey != null) hotKeyManager.unregister(_dictationHotKey!);
    if (_toggleHotKey != null) hotKeyManager.unregister(_toggleHotKey!);
    _permissions.dispose();
    _dictation.dispose();
    super.dispose();
  }

  // ───── Build ─────

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case AppMode.loading:
        return const SizedBox.shrink();
      case AppMode.permissions:
        return _buildPermissions();
      case AppMode.capsule:
        return _buildCapsule();
      case AppMode.settings:
        return _buildSettings();
    }
  }

  Widget _buildPermissions() {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('VoiceInk',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Grant permissions to get started',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13)),
              const SizedBox(height: 32),
              _permTile(
                icon: Icons.mic,
                title: 'Microphone',
                subtitle: 'Required for voice capture',
                granted: _permissions.micGranted,
                buttonLabel: 'Grant',
                onTap: () async {
                  await _permissions.checkMicrophone();
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 16),
              _permTile(
                icon: Icons.accessibility_new,
                title: 'Accessibility',
                subtitle: 'Required for typing text into apps',
                granted: _permissions.accessibilityGranted,
                buttonLabel: 'Open Settings',
                onTap: () => _permissions.openAccessibilitySettings(),
              ),
              const Spacer(),
              Center(
                child: TextButton.icon(
                  onPressed: _recheckPerms,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Check Again'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required String buttonLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: granted
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(granted ? Icons.check_circle : icon,
              color: granted ? Colors.green : Colors.orange, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12)),
              ],
            ),
          ),
          if (!granted)
            ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(buttonLabel, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _buildCapsule() {
    return ListenableBuilder(
      listenable: _dictation,
      builder: (context, _) {
        return GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          onDoubleTap: _openSettings,
          child: Container(
            color: Colors.transparent,
            child: Center(
              child: FloatingIndicator(state: _dictation.state),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettings() {
    return Scaffold(
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
    );
  }
}
