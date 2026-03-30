import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_capture_service.dart';
import 'stt_transcriber.dart';
import 'whisper_cpp_transcriber.dart';
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
  SttTranscriber? _transcriber;

  DictationState _state = DictationState.idle;
  String _lastTranscription = '';
  String? _errorMessage;
  Timer? _chunkTimer;
  bool _transcribing = false;
  String _language = 'auto'; // Language for transcription

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

  DictationService({required this.modelManager, SttTranscriber? transcriber})
      : _transcriber = transcriber;

  Future<void> init() async {
    await _audio.init();

    // If no transcriber was injected, create a default WhisperCppTranscriber
    if (_transcriber == null) {
      final wt = WhisperCppTranscriber();
      await wt.init();
      _transcriber = wt;
      if (wt.isAvailable) {
        debugPrint('[VoiceInk] Whisper binary found at: ${wt.cliPath}');
      } else {
        debugPrint('[VoiceInk] WARNING: whisper-cli not found!');
      }
    } else {
      debugPrint('[VoiceInk] Using injected transcriber: ${_transcriber!.providerName}');
    }

    final prefs = await SharedPreferences.getInstance();
    _cleanup.removeFillers = prefs.getBool('cleanup_fillers') ?? true;
    _cleanup.skipNonSpeech = prefs.getBool('cleanup_nonspeech') ?? true;
    _cleanup.convertPunctuation = prefs.getBool('cleanup_punctuation') ?? true;
    _cleanup.autoCapitalize = prefs.getBool('cleanup_capitalize') ?? true;
    _language = prefs.getString('whisper_language') ?? 'auto';

    writingStyle = WritingStyle.fromString(prefs.getString('writing_style') ?? 'clean');
    dictionary.isEnabled = prefs.getBool('dictionary_enabled') ?? false;

    final savedModel = prefs.getString('selected_model');
    if (savedModel != null && modelManager.isDownloaded(savedModel)) {
      modelManager.selectModel(savedModel);
    }
  }

  /// Replace the transcriber at runtime (e.g., when switching providers).
  void setTranscriber(SttTranscriber transcriber) {
    _transcriber = transcriber;
    notifyListeners();
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

    if (_transcriber == null || !_transcriber!.isAvailable) {
      _errorMessage = 'Speech transcriber not available. Check installation.';
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
  /// Uses immediate restart to minimize audio gap between chunks.
  Future<void> _harvestChunk() async {
    if (_state != DictationState.recording) return;
    if (_transcribing) return; // don't overlap

    _transcribing = true;
    try {
      // Start new recording FIRST, then stop old one — minimizes gap
      // The recorder doesn't support simultaneous start/stop, so we stop then
      // immediately restart. The gap is ~10-50ms which is acceptable.
      final audioPath = await _audio.stopRecording();
      
      // Immediately restart recording for next chunk
      if (_state == DictationState.recording) {
        await _audio.startRecording();
      }

      // Transcribe the completed chunk in the background
      if (audioPath != null && await File(audioPath).exists()) {
        final fileSize = await File(audioPath).length();
        if (fileSize > 500) { // Lower threshold — even short audio may have words
          try {
            final rawText = await _transcriber!.transcribe(
              audioPath: audioPath,
              modelPath: modelManager.selectedModelPath!,
              language: _language,
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
        if (fileSize > 500) { // Lower threshold to capture short utterances
          final rawText = await _transcriber!.transcribe(
            audioPath: audioPath,
            modelPath: modelManager.selectedModelPath!,
            language: _language,
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
