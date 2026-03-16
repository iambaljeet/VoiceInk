import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'services/model_manager.dart';
import 'services/dictation_service.dart';
import 'ui/floating_indicator.dart';
import 'ui/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await hotKeyManager.unregisterAll();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(380, 140),
    minimumSize: Size(300, 100),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setAsFrameless();
    await windowManager.show();
    await windowManager.focus();
  });

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
  bool _initialized = false;
  bool _showSettings = false;
  HotKey? _dictationHotKey;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _modelManager = ModelManager();
    _dictation = DictationService(modelManager: _modelManager);
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      await _modelManager.init();
      await _dictation.init();
      await _registerHotkey();
      setState(() => _initialized = true);
    } catch (e) {
      debugPrint('Initialization error: $e');
      setState(() => _initialized = true);
    }
  }

  Future<void> _registerHotkey() async {
    _dictationHotKey = HotKey(
      key: PhysicalKeyboardKey.space,
      modifiers: [HotKeyModifier.alt],
      scope: HotKeyScope.system,
    );

    await hotKeyManager.register(
      _dictationHotKey!,
      keyDownHandler: (_) async {
        if (_showSettings) return;
        if (_dictation.state == DictationState.idle) {
          await _dictation.startRecording();
          setState(() {});
        }
      },
      keyUpHandler: (_) async {
        if (_dictation.state == DictationState.recording) {
          await _dictation.stopRecordingAndTranscribe();
          setState(() {});
          _startIdleTimer();
        }
      },
    );
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 3), () {
      if (_dictation.state == DictationState.idle) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _idleTimer?.cancel();
    if (_dictationHotKey != null) {
      hotKeyManager.unregister(_dictationHotKey!);
    }
    _dictation.dispose();
    super.dispose();
  }

  void _toggleSettings() {
    setState(() => _showSettings = !_showSettings);
    if (_showSettings) {
      windowManager.setSize(const Size(480, 680));
      windowManager.setMinimumSize(const Size(420, 500));
      windowManager.setAlwaysOnTop(false);
    } else {
      windowManager.setSize(const Size(380, 140));
      windowManager.setMinimumSize(const Size(300, 100));
      windowManager.setAlwaysOnTop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF1a1a2e),
          body: Center(
            child: CircularProgressIndicator(color: Colors.blue),
          ),
        ),
      );
    }

    if (_showSettings) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Scaffold(
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
                  onPressed: _toggleSettings,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: _dictation,
      builder: (context, _) {
        return GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a2e).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mic, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'VoiceInk',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    _buildStatusDot(),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _toggleSettings,
                      child: const Icon(
                        Icons.settings,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => exit(0),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FloatingIndicator(
                  state: _dictation.state,
                  lastText: _dictation.lastTranscription,
                  error: _dictation.errorMessage,
                  onCancel: () async {
                    await _dictation.cancelRecording();
                    setState(() {});
                  },
                ),
                if (_dictation.state == DictationState.idle &&
                    _dictation.lastTranscription.isEmpty &&
                    _dictation.errorMessage == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _modelManager.downloadedModels.isEmpty
                          ? 'Open Settings to download a model'
                          : 'Hold Option+Space to dictate',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusDot() {
    Color color;
    switch (_dictation.state) {
      case DictationState.idle:
        color = _modelManager.downloadedModels.isEmpty
            ? Colors.orange
            : Colors.green;
        break;
      case DictationState.recording:
        color = Colors.red;
        break;
      case DictationState.processing:
        color = Colors.blue;
        break;
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
