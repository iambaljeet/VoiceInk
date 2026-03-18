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
import 'services/whisper_streaming_service.dart';
import 'services/native_stt_service.dart';
import 'services/stt_engine_manager.dart';
import 'services/permission_service.dart';
import 'services/hotkey_service.dart';
import 'services/audio_device_service.dart';
import 'config/app_config.dart';
import 'ui/floating_indicator.dart';
import 'ui/settings_screen.dart';
import 'ui/onboarding_screen.dart';
import 'ui/permission_guard_screen.dart';

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
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: const VoiceInkHome(),
    );
  }
}

enum AppMode { loading, onboarding, permissionRequired, capsule, settings }

class VoiceInkHome extends StatefulWidget {
  const VoiceInkHome({super.key});

  @override
  State<VoiceInkHome> createState() => _VoiceInkHomeState();
}

class _VoiceInkHomeState extends State<VoiceInkHome> with WindowListener {
  late ModelManager _modelManager;
  late DictationService _dictation;
  final SttEngineManager _engineManager = SttEngineManager();
  final NativeSttService _nativeStt = NativeSttService();
  late WhisperStreamingService _whisperStreaming;
  final PermissionService _permissions = PermissionService();
  final HotkeyService _hotkeyService = HotkeyService();
  final AudioDeviceService _audioDevice = AudioDeviceService();
  SystemTray? _systemTray;

  AppMode _mode = AppMode.loading;
  bool _capsuleVisible = true;
  bool _openingSettings = false;
  HotKey? _toggleHotKey;

  // Push-to-talk state
  DateTime? _keyDownTime;
  bool _pttActive = false; // true while key is held and recording
  DictationState _capsuleState = DictationState.idle;
  static const _minHoldMs = 200; // ignore taps shorter than this

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _modelManager = ModelManager();
    _dictation = DictationService(modelManager: _modelManager);
    _whisperStreaming = WhisperStreamingService(modelManager: _modelManager);
    _engineManager.addListener(_onEngineChange);
    _nativeStt.addListener(_onSttChange);
    _whisperStreaming.addListener(_onSttChange);
    _boot();
  }

  Future<void> _boot() async {
    debugPrint('[VoiceInk] Booting...');

    final onboarded = await OnboardingScreen.isComplete();
    if (!onboarded) {
      _mode = AppMode.onboarding;
      if (mounted) setState(() {});
      return;
    }

    await _goLive();
  }

  void _onOnboardingComplete() {
    _goLive();
  }

  void _onPermissionsRestored() {
    _goLive();
  }

  Future<void> _goLive() async {
    // Init services that need to run after onboarding
    await _hotkeyService.init();
    await _audioDevice.init();

    // Check permissions — if any missing, show guard
    await _permissions.checkAll();
    if (!_permissions.allGranted) {
      _mode = AppMode.permissionRequired;
      if (mounted) setState(() {});
      return;
    }

    _mode = AppMode.capsule;
    if (mounted) setState(() {});
    await _setupCapsuleWindow();

    try {
      await _engineManager.init();
      await _modelManager.init();
      debugPrint('[VoiceInk] Models: ${_modelManager.downloadedModels.length}');
      await _dictation.init();

      final nativeAvail = await NativeSttService.checkAvailability();
      _engineManager.setNativeAvailable(nativeAvail);
      debugPrint('[VoiceInk] Native STT available: $nativeAvail');

      if (_engineManager.engine == SttEngine.native && nativeAvail) {
        await _nativeStt.init();
      }
      await _whisperStreaming.init();

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

  Future<void> _setupCapsuleWindow() async {
    await windowManager.setMaximumSize(const Size(800, 200));
    await windowManager.setMinimumSize(const Size(120, 56));
    await windowManager.setSize(const Size(200, 56));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setHasShadow(false);
    await windowManager.setPosition(const Offset(600, 40));

    await windowManager.show();
    await windowManager.focus();
    Future.delayed(const Duration(milliseconds: 100), () async {
      await windowManager.setSize(const Size(200, 56));
    });
  }

  // ───── System tray ─────

  Future<void> _initSystemTray() async {
    final iconPath = await _extractTrayIcon();
    if (iconPath == null) return;

    _systemTray = SystemTray();
    await _systemTray!.initSystemTray(
      title: '',
      toolTip: AppConfig.trayTooltip,
      iconPath: iconPath,
    );

    await _rebuildTrayMenu();

    _systemTray!.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick ||
          eventName == kSystemTrayEventRightClick) {
        _systemTray!.popUpContextMenu();
      }
    });
  }

  Future<void> _rebuildTrayMenu() async {
    if (_systemTray == null) return;
    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: 'Hold ${_hotkeyService.preset.label} to Dictate',
        onClicked: (_) {},
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
        label: 'Quit ${AppConfig.appName}',
        onClicked: (_) => exit(0),
      ),
    ]);
    await _systemTray!.setContextMenu(menu);
  }

  Future<String?> _extractTrayIcon() async {
    try {
      final data = await rootBundle.load(AppConfig.trayIconAsset);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/voiceink_tray.png');
      await file.writeAsBytes(data.buffer.asUint8List());
      return file.path;
    } catch (e) {
      debugPrint('[VoiceInk] Tray icon error: $e');
      return null;
    }
  }

  // ───── Engine helpers ─────

  void _onEngineChange() {
    if (mounted) setState(() {});
  }

  void _onSttChange() {
    if (mounted) setState(() {});
  }

  // ───── Push-to-talk (hold-to-record, release-to-transcribe) ─────

  Future<void> _onPttKeyDown() async {
    if (_mode == AppMode.settings || _mode == AppMode.onboarding || _mode == AppMode.permissionRequired) return;
    if (_pttActive) return; // already recording

    _keyDownTime = DateTime.now();
    _pttActive = true;

    // Show capsule if hidden
    if (!_capsuleVisible) _showCapsule();

    // Transition to recording
    setState(() => _capsuleState = DictationState.recording);
    await _startActiveEngine();
  }

  Future<void> _onPttKeyUp() async {
    if (!_pttActive) return;
    _pttActive = false;

    // Check minimum hold duration to ignore accidental taps
    if (_keyDownTime != null) {
      final held = DateTime.now().difference(_keyDownTime!).inMilliseconds;
      if (held < _minHoldMs) {
        debugPrint('[VoiceInk] PTT tap too short (${held}ms), ignoring');
        await _stopActiveEngine();
        setState(() => _capsuleState = DictationState.idle);
        return;
      }
    }

    // Transition to processing (blue "Typing…")
    setState(() => _capsuleState = DictationState.processing);

    // Stop recording — this triggers transcription + text injection
    await _stopActiveEngine();

    // Brief pause so user sees the "Typing…" state
    await Future.delayed(const Duration(milliseconds: 600));

    // Back to idle
    if (mounted) setState(() => _capsuleState = DictationState.idle);
  }

  Future<void> _startActiveEngine() async {
    switch (_engineManager.engine) {
      case SttEngine.native:
        if (!_nativeStt.initialized) await _nativeStt.init();
        await _nativeStt.startListening();
        break;
      case SttEngine.model:
        if (_whisperStreaming.isWhisperAvailable &&
            _modelManager.selectedModelPath != null) {
          await _whisperStreaming.startRecording(
            device: _audioDevice.selectedDevice,
          );
        } else {
          await _dictation.startRecording();
        }
        break;
    }
    if (mounted) setState(() {});
  }

  Future<void> _stopActiveEngine() async {
    switch (_engineManager.engine) {
      case SttEngine.native:
        await _nativeStt.stopListening();
        break;
      case SttEngine.model:
        if (_whisperStreaming.isRecording) {
          await _whisperStreaming.stopRecording();
        } else if (_dictation.isRecording) {
          await _dictation.stopRecording();
        }
        break;
    }
    if (mounted) setState(() {});
  }

  // ───── Hotkeys ─────

  Future<void> _registerHotkeys() async {
    // Push-to-talk via HotkeyService
    await _hotkeyService.registerPushToTalk(
      _onPttKeyDown,
      _onPttKeyUp,
    );

    // Capsule visibility toggle: ⌥V
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
    if (_openingSettings) return;
    _openingSettings = true;

    try {
      _mode = AppMode.settings;
      if (mounted) setState(() {});

      await windowManager.setMaximumSize(const Size(800, 900));
      await windowManager.setMinimumSize(const Size(420, 500));
      await windowManager.setSize(const Size(480, 680));
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setHasShadow(true);
      await windowManager.setBackgroundColor(const Color(0xFF1a1a2e));

      _capsuleVisible = true;
      await windowManager.show();
      await windowManager.center();

      await Future.delayed(const Duration(milliseconds: 100));
      await windowManager.focus();
    } catch (e) {
      debugPrint('[VoiceInk] Settings open error: $e');
    } finally {
      _openingSettings = false;
    }
  }

  void _closeSettings() {
    _mode = AppMode.capsule;
    if (mounted) setState(() {});
    _setupCapsuleWindow();
    // Rebuild tray menu in case shortcut changed
    _rebuildTrayMenu();
  }

  // ───── Window listener ─────

  @override
  void onWindowClose() async {
    _hideCapsule();
  }

  @override
  void onWindowFocus() {
    if (_mode == AppMode.capsule) {
      _permissions.checkAll().then((_) {
        if (!_permissions.allGranted && mounted) {
          setState(() {
            _mode = AppMode.permissionRequired;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _hotkeyService.unregister();
    if (_toggleHotKey != null) hotKeyManager.unregister(_toggleHotKey!);
    _permissions.dispose();
    _dictation.dispose();
    _nativeStt.removeListener(_onSttChange);
    _nativeStt.dispose();
    _whisperStreaming.removeListener(_onSttChange);
    _whisperStreaming.dispose();
    _engineManager.removeListener(_onEngineChange);
    _engineManager.dispose();
    _hotkeyService.dispose();
    _audioDevice.dispose();
    super.dispose();
  }

  // ───── Build ─────

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case AppMode.loading:
        return const SizedBox.shrink();
      case AppMode.onboarding:
        return OnboardingScreen(
          permissions: _permissions,
          audioDevice: _audioDevice,
          hotkeyService: _hotkeyService,
          engineManager: _engineManager,
          modelManager: _modelManager,
          onComplete: _onOnboardingComplete,
        );
      case AppMode.permissionRequired:
        return PermissionGuardScreen(
          permissions: _permissions,
          onAllGranted: _onPermissionsRestored,
        );
      case AppMode.capsule:
        return _buildCapsule();
      case AppMode.settings:
        return _buildSettings();
    }
  }

  Widget _buildCapsule() {
    return ListenableBuilder(
      listenable: Listenable.merge([_dictation, _nativeStt, _whisperStreaming, _engineManager]),
      builder: (context, _) {
        return GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          onDoubleTap: _openSettings,
          child: Container(
            color: Colors.transparent,
            child: Center(
              child: FloatingIndicator(
                state: _capsuleState,
                shortcutLabel: _hotkeyService.preset.label,
              ),
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
            engineManager: _engineManager,
            whisperStreaming: _whisperStreaming,
            hotkeyService: _hotkeyService,
            audioDevice: _audioDevice,
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
