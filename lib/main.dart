import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'services/model_manager.dart';
import 'services/dictation_service.dart';
import 'services/whisper_streaming_service.dart';
import 'services/stt_engine_manager.dart';
import 'services/stt_transcriber.dart';
import 'services/whisper_cpp_transcriber.dart';
import 'services/sherpa_onnx_transcriber.dart';
import 'services/sherpa_model_manager.dart';
import 'services/permission_service.dart';
import 'services/hotkey_service.dart';
import 'services/audio_device_service.dart';
import 'services/database_service.dart';
import 'services/dictionary_service.dart';
import 'services/stats_service.dart';
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
  late SherpaModelManager _sherpaModelManager;
  late DictationService _dictation;
  final SttEngineManager _engineManager = SttEngineManager();
  late WhisperStreamingService _whisperStreaming;
  SttTranscriber? _activeTranscriber;
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
  bool _capsuleHovered = false;
  bool _capsuleBorderVisible = true;
  static const _hoverChannel = MethodChannel('com.voiceink/hover');
  static const _windowChannel = MethodChannel('com.voiceink/window');
  final _indicatorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _hoverChannel.setMethodCallHandler(_handleHoverCall);
    _modelManager = ModelManager();
    _sherpaModelManager = SherpaModelManager();
    _dictation = DictationService(modelManager: _modelManager);
    _whisperStreaming = WhisperStreamingService(modelManager: _modelManager);
    _engineManager.addListener(_onEngineChange);
    _whisperStreaming.addListener(_onSttChange);
    _boot();
  }

  Future<dynamic> _handleHoverCall(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'mouseMove':
        final args = call.arguments as Map;
        final x = (args['x'] as num).toDouble();
        final y = (args['y'] as num).toDouble();
        _hitTestCapsule(Offset(x, y));
        break;
      case 'mouseExit':
        if (_capsuleHovered) {
          setState(() => _capsuleHovered = false);
          // Re-enable click-through when mouse leaves the pill (macOS)
          if (Platform.isMacOS) {
            _windowChannel.invokeMethod('setClickThrough', true);
          }
        }
        break;
    }
  }

  void _hitTestCapsule(Offset windowPoint) {
    final renderBox =
        _indicatorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final widgetPos = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    // Extra padding so the tiny idle pill (48×6) is easy to target
    const pad = 10.0;
    final rect = Rect.fromLTWH(
      widgetPos.dx - pad,
      widgetPos.dy - pad,
      size.width + pad * 2,
      size.height + pad * 2,
    );

    final inside = rect.contains(windowPoint);
    if (inside != _capsuleHovered) {
      setState(() => _capsuleHovered = inside);
      // Toggle click-through: disable when hovering the pill so it receives
      // clicks/drags, re-enable when mouse leaves so clicks pass through.
      if (Platform.isMacOS) {
        _windowChannel.invokeMethod('setClickThrough', !inside);
      }
    }
  }

  Future<void> _setCapsuleBorderVisible(bool value) async {
    setState(() => _capsuleBorderVisible = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('capsule_border_visible', value);
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

    // Load capsule appearance preference
    final prefs = await SharedPreferences.getInstance();
    _capsuleBorderVisible = prefs.getBool('capsule_border_visible') ?? true;

    try {
      await _engineManager.init();
      await _modelManager.init();
      await _sherpaModelManager.init();
      debugPrint('[VoiceInk] Models: ${_modelManager.downloadedModels.length}');

      // Create transcriber based on selected provider
      await _createTranscriber();

      // Initialize database and new services
      await DatabaseService.instance.initialize();
      await DictionaryService.instance.init();
      await StatsService.instance.init();
      debugPrint('[VoiceInk] Database & services initialized');

      await _dictation.init();

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

    // Enable capsule mode (click-through on macOS)
    if (Platform.isMacOS) {
      _windowChannel.invokeMethod('setCapsuleMode', true);
    }

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
        label: 'Hold ${_hotkeyService.activeLabel} to Dictate',
        onClicked: (_) {},
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Show/Hide Capsule  ${Platform.isMacOS ? '⌥V' : 'Alt+V'}',
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
      final file = File(p.join(dir.path, 'voiceink_tray.png'));
      await file.writeAsBytes(data.buffer.asUint8List());
      return file.path;
    } catch (e) {
      debugPrint('[VoiceInk] Tray icon error: $e');
      return null;
    }
  }

  // ───── Engine helpers ─────

  /// Create and configure the appropriate transcriber based on selected provider.
  Future<void> _createTranscriber() async {
    _activeTranscriber?.dispose();

    switch (_engineManager.provider) {
      case SttProvider.whisperCpp:
        final wt = WhisperCppTranscriber();
        await wt.init();
        _activeTranscriber = wt;
        debugPrint('[VoiceInk] Whisper binary found: ${wt.isAvailable}');
        if (wt.isAvailable) {
          debugPrint('[VoiceInk] Whisper CLI: ${wt.cliPath}');
        }
        break;
      case SttProvider.sherpaOnnx:
        final st = SherpaOnnxTranscriber();
        await st.init();
        // Load selected sherpa model if available
        final paths = _sherpaModelManager.selectedModelPaths;
        if (paths != null && st.isAvailable) {
          st.loadModel(paths);
        }
        _activeTranscriber = st;
        debugPrint('[VoiceInk] Sherpa-ONNX available: ${st.isAvailable}');
        break;
    }

    // Update services with new transcriber
    if (_activeTranscriber != null) {
      _whisperStreaming.setTranscriber(_activeTranscriber!);
      _dictation.setTranscriber(_activeTranscriber!);
    }
  }

  void _onEngineChange() {
    _createTranscriber();
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
    if (_whisperStreaming.isWhisperAvailable &&
        _modelManager.selectedModelPath != null) {
      await _whisperStreaming.startRecording(
        device: _audioDevice.selectedDevice,
      );
    } else {
      await _dictation.startRecording();
    }
    if (mounted) setState(() {});
  }

  Future<void> _stopActiveEngine() async {
    if (_whisperStreaming.isRecording) {
      await _whisperStreaming.stopRecording();
    } else if (_dictation.isRecording) {
      await _dictation.stopRecording();
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

      // Disable capsule mode so settings window is fully interactive
      if (Platform.isMacOS) {
        _windowChannel.invokeMethod('setCapsuleMode', false);
      }

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
    // If settings is open, return to capsule instead of hiding everything.
    if (_mode == AppMode.settings) {
      _closeSettings();
      return;
    }
    _hideCapsule();
  }

  @override
  void onWindowBlur() {
    // When settings window loses focus (clicked away, taskbar hide, etc.),
    // collapse back to the floating capsule so it stays visible.
    if (_mode == AppMode.settings) {
      _closeSettings();
    }
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
    _whisperStreaming.removeListener(_onSttChange);
    _whisperStreaming.dispose();
    _engineManager.removeListener(_onEngineChange);
    _engineManager.dispose();
    _activeTranscriber?.dispose();
    _sherpaModelManager.dispose();
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
      listenable: Listenable.merge([_dictation, _whisperStreaming, _engineManager]),
      builder: (context, _) {
        // Only the pill area is interactive (drag + double-tap).
        // The transparent background passes clicks through to apps behind.
        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startDragging(),
            onDoubleTap: _openSettings,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: FloatingIndicator(
                key: _indicatorKey,
                state: _capsuleState,
                shortcutLabel: _hotkeyService.activeLabel,
                isHovered: _capsuleHovered,
                showBorder: _capsuleBorderVisible,
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
            sherpaModelManager: _sherpaModelManager,
            dictationService: _dictation,
            engineManager: _engineManager,
            whisperStreaming: _whisperStreaming,
            hotkeyService: _hotkeyService,
            audioDevice: _audioDevice,
            capsuleBorderVisible: _capsuleBorderVisible,
            onCapsuleBorderChanged: _setCapsuleBorderVisible,
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
