import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_capture_service.dart';
import 'whisper_service.dart';
import 'text_cleanup_service.dart';
import 'text_injection_service.dart';
import 'model_manager.dart';
import 'dictionary_service.dart';
import 'stats_service.dart';
import '../models/writing_style.dart';

enum DictationState { idle, recording, processing }

/// Streaming dictation: records in chunks, transcribes each, injects text live.
/// Toggle mode: press hotkey once to start, again to stop.
class DictationService extends ChangeNotifier {
  final AudioCaptureService _audio = AudioCaptureService();
  final TextCleanupService _cleanup = TextCleanupService();
  final TextInjectionService _injection = TextInjectionService();
  final ModelManager modelManager;
  WhisperService? _whisper;

  DictationState _state = DictationState.idle;
  String _lastTranscription = '';
  String? _errorMessage;
  Timer? _chunkTimer;
  bool _transcribing = false;

  // Streaming config
  static const _chunkDuration = Duration(seconds: 3);

  DictationState get state => _state;
  String get lastTranscription => _lastTranscription;
  String? get errorMessage => _errorMessage;
  bool get isRecording => _state == DictationState.recording;
  bool get isProcessing => _state == DictationState.processing;

  WritingStyle writingStyle = WritingStyle.clean;

  DictionaryService get dictionary => DictionaryService.instance;
  StatsService get stats => StatsService.instance;

  DictationService({required this.modelManager});

  Future<void> init() async {
    await _audio.init();

    // Desktop: use whisper CLI binary
    final whisperPath = await _resolveWhisperPath();
    if (whisperPath != null) {
      _whisper = WhisperService(whisperPath);
      debugPrint('[VoiceInk] Whisper binary found at: $whisperPath');
    } else {
      debugPrint('[VoiceInk] WARNING: whisper-cli not found!');
    }

    final prefs = await SharedPreferences.getInstance();
    _cleanup.removeFillers = prefs.getBool('cleanup_fillers') ?? true;
    _cleanup.skipNonSpeech = prefs.getBool('cleanup_nonspeech') ?? true;
    _cleanup.convertPunctuation = prefs.getBool('cleanup_punctuation') ?? true;
    _cleanup.autoCapitalize = prefs.getBool('cleanup_capitalize') ?? true;

    writingStyle = WritingStyle.fromString(prefs.getString('writing_style') ?? 'clean');
    dictionary.isEnabled = prefs.getBool('dictionary_enabled') ?? false;

    final savedModel = prefs.getString('selected_model');
    if (savedModel != null && modelManager.isDownloaded(savedModel)) {
      modelManager.selectModel(savedModel);
    }
  }

  Future<String?> _resolveWhisperPath() async {
    final execPath = Platform.resolvedExecutable;
    final appDir = File(execPath).parent.path;
    final ext = Platform.isWindows ? '.exe' : '';

    final candidates = [
      '$appDir/../Resources/whisper-cli$ext',
      '$appDir/whisper-cli$ext',
    ];

    final cwd = Directory.current.path;
    candidates.add('$cwd/native/whisper.cpp/build/bin/whisper-cli$ext');

    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }

    // Check PATH
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(cmd, ['whisper-cli']);
      if (result.exitCode == 0) return (result.stdout as String).trim();
    } catch (_) {}

    return null;
  }

  Future<bool> hasPermission() async {
    return await _audio.hasPermission();
  }

  /// Toggle recording on/off. This is the main entry point.
  Future<void> toggleRecording() async {
    if (_state == DictationState.idle) {
      await _startStreaming();
    } else if (_state == DictationState.recording) {
      await _stopStreaming();
    }
    // If processing, ignore (it'll finish soon)
  }

  /// Start recording (for push-to-talk).
  Future<void> startRecording() async {
    if (_state == DictationState.idle) await _startStreaming();
  }

  /// Stop recording (for push-to-talk).
  Future<void> stopRecording() async {
    if (_state == DictationState.recording) await _stopStreaming();
  }

  Future<void> _startStreaming() async {
    _errorMessage = null;

    if (_whisper == null) {
      _errorMessage = 'Whisper binary not found. Check installation.';
      notifyListeners();
      return;
    }

    if (modelManager.selectedModelPath == null) {
      _errorMessage = 'No model selected. Download one in Settings.';
      notifyListeners();
      return;
    }

    try {
      await _audio.startRecording();
      _state = DictationState.recording;
      _lastTranscription = '';
      notifyListeners();

      // Start chunk timer — every N seconds, harvest audio and transcribe
      _chunkTimer = Timer.periodic(_chunkDuration, (_) => _harvestChunk());
    } catch (e) {
      _errorMessage = 'Mic error: $e';
      _state = DictationState.idle;
      notifyListeners();
    }
  }

  /// Harvest current chunk: stop recording, transcribe, start new recording
  Future<void> _harvestChunk() async {
    if (_state != DictationState.recording) return;
    if (_transcribing) return; // don't overlap

    _transcribing = true;
    try {
      // Stop current recording
      final audioPath = await _audio.stopRecording();
      
      // Immediately start a new recording for the next chunk
      if (_state == DictationState.recording) {
        await _audio.startRecording();
      }

      // Transcribe the completed chunk in the background
      if (audioPath != null && await File(audioPath).exists()) {
        final fileSize = await File(audioPath).length();
        if (fileSize > 1000) { // skip tiny files (silence)
          try {
            final rawText = await _whisper!.transcribe(
              audioPath: audioPath,
              modelPath: modelManager.selectedModelPath!,
            );

            final cleaned = await _processTranscription(rawText);
            if (cleaned.isNotEmpty) {
              _lastTranscription += ((_lastTranscription.isNotEmpty) ? ' ' : '') + cleaned;
              notifyListeners();
              await _injection.injectText('$cleaned ');
            }
          } catch (e) {
            debugPrint('[VoiceInk] Whisper transcription error: $e');
          }
        }
        // Clean up chunk file
        try { await File(audioPath).delete(); } catch (_) {}
      }
    } catch (e) {
      debugPrint('[VoiceInk] Chunk transcription error: $e');
    } finally {
      _transcribing = false;
    }
  }

  Future<void> _stopStreaming() async {
    _chunkTimer?.cancel();
    _chunkTimer = null;

    // Grab final audio, then immediately go idle (no visible processing state)
    String? audioPath;
    try {
      audioPath = await _audio.stopRecording();
    } catch (_) {}

    _state = DictationState.idle;
    notifyListeners();

    // Process final chunk in background (fire-and-forget)
    if (audioPath != null) {
      _transcribeFinalChunk(audioPath);
    } else {
      _audio.cleanup();
    }
  }

  Future<void> _transcribeFinalChunk(String audioPath) async {
    try {
      if (await File(audioPath).exists()) {
        final fileSize = await File(audioPath).length();
        if (fileSize > 1000) {
          final rawText = await _whisper!.transcribe(
            audioPath: audioPath,
            modelPath: modelManager.selectedModelPath!,
          );
          final cleaned = await _processTranscription(rawText);
          if (cleaned.isNotEmpty) {
            await _injection.injectText('$cleaned ');
          }
        }
        try { await File(audioPath).delete(); } catch (_) {}
      }
    } catch (e) {
      debugPrint('[VoiceInk] Final chunk error: $e');
    }
    await _audio.cleanup();
  }

  Future<void> cancelRecording() async {
    _chunkTimer?.cancel();
    _chunkTimer = null;
    await _audio.cancelRecording();
    _state = DictationState.idle;
    _lastTranscription = '';
    notifyListeners();
    await _audio.cleanup();
  }

  Future<void> savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cleanup_fillers', _cleanup.removeFillers);
    await prefs.setBool('cleanup_nonspeech', _cleanup.skipNonSpeech);
    await prefs.setBool('cleanup_punctuation', _cleanup.convertPunctuation);
    await prefs.setBool('cleanup_capitalize', _cleanup.autoCapitalize);
    await prefs.setString('writing_style', writingStyle.toStorageString());
    await prefs.setBool('dictionary_enabled', dictionary.isEnabled);
    if (modelManager.selectedModelId != null) {
      await prefs.setString('selected_model', modelManager.selectedModelId!);
    }
  }

  TextCleanupService get cleanup => _cleanup;

  /// Full post-transcription pipeline: cleanup → writing style → dictionary → stats.
  Future<String> _processTranscription(String rawText) async {
    // 1. Standard cleanup (fillers, non-speech, punctuation, capitalize)
    //    Skip cleanup entirely for Verbatim style
    String cleaned;
    if (writingStyle == WritingStyle.verbatim) {
      cleaned = rawText.trim();
    } else {
      cleaned = _cleanup.process(rawText);
    }

    // 2. Writing style transform (formal, chat, etc.)
    cleaned = writingStyle.apply(cleaned);

    // 3. Dictionary replacements (fuzzy matching, symbol shortcuts)
    cleaned = dictionary.applyReplacements(cleaned);

    // 4. Update stats
    final wordCount = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    await stats.recordTranscription(wordCount: wordCount);

    return cleaned;
  }

  @override
  void dispose() {
    _chunkTimer?.cancel();
    _audio.dispose();
    super.dispose();
  }
}
