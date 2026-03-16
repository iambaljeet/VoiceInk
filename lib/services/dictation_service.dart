import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_capture_service.dart';
import 'whisper_service.dart';
import 'text_cleanup_service.dart';
import 'text_injection_service.dart';
import 'model_manager.dart';

enum DictationState { idle, recording, processing }

/// Main orchestrator that ties audio → transcription → text injection together
class DictationService extends ChangeNotifier {
  final AudioCaptureService _audio = AudioCaptureService();
  final TextCleanupService _cleanup = TextCleanupService();
  final TextInjectionService _injection = TextInjectionService();
  final ModelManager modelManager;
  WhisperService? _whisper;

  DictationState _state = DictationState.idle;
  String _lastTranscription = '';
  String? _errorMessage;

  DictationState get state => _state;
  String get lastTranscription => _lastTranscription;
  String? get errorMessage => _errorMessage;
  bool get isRecording => _state == DictationState.recording;
  bool get isProcessing => _state == DictationState.processing;

  DictationService({required this.modelManager});

  Future<void> init() async {
    await _audio.init();

    // Resolve whisper binary path
    final whisperPath = await _resolveWhisperPath();
    if (whisperPath != null) {
      _whisper = WhisperService(whisperPath);
    }

    // Load preferences
    final prefs = await SharedPreferences.getInstance();
    _cleanup.removeFillers = prefs.getBool('cleanup_fillers') ?? true;
    _cleanup.convertPunctuation = prefs.getBool('cleanup_punctuation') ?? true;
    _cleanup.autoCapitalize = prefs.getBool('cleanup_capitalize') ?? true;

    final savedModel = prefs.getString('selected_model');
    if (savedModel != null && modelManager.isDownloaded(savedModel)) {
      modelManager.selectModel(savedModel);
    }
  }

  Future<String?> _resolveWhisperPath() async {
    // Check bundled whisper-cli in app resources
    final execPath = Platform.resolvedExecutable;
    final appDir = File(execPath).parent.path;

    // For development: check in native/whisper.cpp/build/bin/
    final devPaths = [
      '$appDir/../Resources/whisper-cli',
      '$appDir/whisper-cli',
    ];

    // Also check the development build path
    final cwd = Directory.current.path;
    devPaths.add('$cwd/native/whisper.cpp/build/bin/whisper-cli');

    // Hardcoded dev path as fallback
    devPaths.add(
      '/Users/baljeet/FlutterWorkspace/voice_ink/native/whisper.cpp/build/bin/whisper-cli',
    );

    for (final path in devPaths) {
      if (await File(path).exists()) {
        return path;
      }
    }

    // Check PATH
    try {
      final result = await Process.run('which', ['whisper-cli']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}

    return null;
  }

  Future<bool> hasPermission() async {
    return await _audio.hasPermission();
  }

  /// Start recording audio
  Future<void> startRecording() async {
    if (_state != DictationState.idle) return;

    _errorMessage = null;

    if (_whisper == null) {
      _errorMessage = 'Whisper binary not found. Check installation.';
      notifyListeners();
      return;
    }

    if (modelManager.selectedModelPath == null) {
      _errorMessage = 'No model selected. Download a model in Settings.';
      notifyListeners();
      return;
    }

    try {
      await _audio.startRecording();
      _state = DictationState.recording;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to start recording: $e';
      notifyListeners();
    }
  }

  /// Stop recording and process audio
  Future<void> stopRecordingAndTranscribe() async {
    if (_state != DictationState.recording) return;

    _state = DictationState.processing;
    notifyListeners();

    try {
      final audioPath = await _audio.stopRecording();
      if (audioPath == null) {
        _state = DictationState.idle;
        _errorMessage = 'No audio recorded';
        notifyListeners();
        return;
      }

      // Transcribe
      final rawText = await _whisper!.transcribe(
        audioPath: audioPath,
        modelPath: modelManager.selectedModelPath!,
      );

      // Clean up text
      final cleanedText = _cleanup.process(rawText);
      _lastTranscription = cleanedText;

      if (cleanedText.isNotEmpty) {
        // Inject text at cursor
        await _injection.injectText(cleanedText);
      }

      _state = DictationState.idle;
      notifyListeners();

      // Clean up temp file
      try {
        await File(audioPath).delete();
      } catch (_) {}
    } catch (e) {
      _state = DictationState.idle;
      _errorMessage = 'Transcription failed: $e';
      notifyListeners();
    }
  }

  /// Cancel current recording
  Future<void> cancelRecording() async {
    if (_state == DictationState.recording) {
      await _audio.cancelRecording();
      _state = DictationState.idle;
      notifyListeners();
    }
  }

  Future<void> savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cleanup_fillers', _cleanup.removeFillers);
    await prefs.setBool('cleanup_punctuation', _cleanup.convertPunctuation);
    await prefs.setBool('cleanup_capitalize', _cleanup.autoCapitalize);
    if (modelManager.selectedModelId != null) {
      await prefs.setString('selected_model', modelManager.selectedModelId!);
    }
  }

  TextCleanupService get cleanup => _cleanup;

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }
}
