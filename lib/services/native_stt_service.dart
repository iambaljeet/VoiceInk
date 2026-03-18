import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

import 'text_cleanup_service.dart';
import 'text_injection_service.dart';
import 'dictionary_service.dart';
import 'stats_service.dart';
import '../models/writing_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight real-time STT using the platform's built-in speech engine.
/// macOS: Apple SFSpeechRecognizer  |  Windows: platform speech recognition
/// Zero model download required. Works out of the box.
class NativeSttService extends ChangeNotifier {
  final SpeechToText _speech = SpeechToText();
  final TextCleanupService _cleanup = TextCleanupService();
  final TextInjectionService _injection = TextInjectionService();

  bool _initialized = false;
  bool _available = false;
  bool _isListening = false;
  String _currentText = '';
  String _committedText = '';
  String? _errorMessage;

  // Auto-restart timer for continuous listening
  Timer? _restartTimer;

  // Track the last partial text so we can commit it if stop() doesn't
  // deliver a final result.
  String _lastPartialText = '';
  bool _finalResultReceived = false;

  bool get initialized => _initialized;
  bool get available => _available;
  bool get isRecording => _isListening;
  String get currentText => _committedText + _currentText;
  String? get errorMessage => _errorMessage;

  /// Check if native speech recognition is available on this device.
  /// Call this before showing the "System Speech" option to the user.
  static Future<bool> checkAvailability() async {
    try {
      final speech = SpeechToText();
      final available = await speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
      return available;
    } catch (e) {
      debugPrint('[NativeSTT] Availability check failed: $e');
      return false;
    }
  }

  Future<bool> init() async {
    if (_initialized) return _available;

    try {
      _available = await _speech.initialize(
        onError: _onError,
        onStatus: _onStatus,
      );
      _initialized = true;
      debugPrint('[NativeSTT] Initialized: available=$_available');
      notifyListeners();
      return _available;
    } catch (e) {
      _errorMessage = 'Speech recognition not available: $e';
      _initialized = true;
      _available = false;
      debugPrint('[NativeSTT] Init error: $e');
      notifyListeners();
      return false;
    }
  }

  Future<void> startListening() async {
    if (_isListening) return;
    if (!_initialized) await init();
    if (!_available) {
      _errorMessage = 'Speech recognition not available on this device';
      notifyListeners();
      return;
    }

    _errorMessage = null;
    _currentText = '';
    _committedText = '';
    _lastPartialText = '';
    _finalResultReceived = false;

    await _startSession();
  }

  Future<void> _startSession() async {
    try {
      _finalResultReceived = false;
      await _speech.listen(
        onResult: _onResult,
        listenFor: const Duration(seconds: 120),
        pauseFor: const Duration(seconds: 60),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
      );
      _isListening = true;
      notifyListeners();
      debugPrint('[NativeSTT] Listening started');
    } catch (e) {
      _errorMessage = 'Failed to start listening: $e';
      _isListening = false;
      notifyListeners();
      debugPrint('[NativeSTT] Start error: $e');
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    final text = result.recognizedWords.trim();

    if (result.finalResult) {
      _finalResultReceived = true;
      // Commit this segment
      if (text.isNotEmpty) {
        _processAndInject(text);
      } else {
        _currentText = '';
        _lastPartialText = '';
        notifyListeners();
      }

      // Auto-restart for continuous listening
      if (_isListening) {
        _scheduleRestart();
      }
    } else {
      // Partial result — show in UI but don't inject yet
      _currentText = text;
      _lastPartialText = text;
      notifyListeners();
    }
  }

  Future<void> _processAndInject(String text) async {
    final cleaned = await _postProcess(text);
    if (cleaned.isNotEmpty) {
      _injection.injectText('$cleaned ');
      _committedText += '$cleaned ';
    }
    _currentText = '';
    _lastPartialText = '';
    notifyListeners();
  }

  void _onError(SpeechRecognitionError error) {
    debugPrint('[NativeSTT] Error: ${error.errorMsg} (permanent=${error.permanent})');
    if (error.permanent) {
      _errorMessage = 'Speech error: ${error.errorMsg}';
      _isListening = false;
      notifyListeners();
    } else if (_isListening) {
      // Transient error — auto-restart with stop first
      _scheduleRestart(delayMs: 500);
    }
  }

  void _onStatus(String status) {
    debugPrint('[NativeSTT] Status: $status');
    if (status == 'done' && _isListening) {
      // Session ended naturally — restart for continuous listening
      _scheduleRestart();
    }
  }

  /// Schedule a restart: stop the current session cleanly, then start a new one.
  void _scheduleRestart({int delayMs = 50}) {
    _restartTimer?.cancel();
    _restartTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_isListening) _restartSession();
    });
  }

  Future<void> _restartSession() async {
    if (!_isListening) return;
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('[NativeSTT] Stop before restart error: $e');
    }
    // Minimal delay — just enough for the engine to release
    await Future.delayed(const Duration(milliseconds: 50));
    if (_isListening) {
      debugPrint('[NativeSTT] Restarting session...');
      await _startSession();
    }
  }

  Future<void> stopListening() async {
    _restartTimer?.cancel();
    _restartTimer = null;

    final wasListening = _isListening;
    _isListening = false;

    // Save pending partial text in case stop() doesn't deliver a final result
    final pendingPartial = _lastPartialText;
    _finalResultReceived = false;

    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('[NativeSTT] Stop error: $e');
    }

    // Give the platform a moment to deliver the final result callback
    if (wasListening && pendingPartial.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // If no final result was delivered for the pending text, commit it now
    if (!_finalResultReceived && pendingPartial.isNotEmpty) {
      debugPrint('[NativeSTT] No final result received — committing partial: $pendingPartial');
      final cleaned = await _postProcess(pendingPartial);
      if (cleaned.isNotEmpty) {
        _injection.injectText('$cleaned ');
        _committedText += '$cleaned ';
      }
    }

    _currentText = '';
    _lastPartialText = '';
    notifyListeners();
    debugPrint('[NativeSTT] Listening stopped');
  }

  Future<void> toggleListening() async {
    if (_isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  TextCleanupService get cleanup => _cleanup;

  /// Shared post-processing: cleanup → writing style → dictionary → stats
  Future<String> _postProcess(String rawText) async {
    final prefs = await SharedPreferences.getInstance();
    final style = WritingStyle.fromString(prefs.getString('writing_style') ?? 'clean');

    String cleaned;
    if (style == WritingStyle.verbatim) {
      cleaned = rawText.trim();
    } else {
      cleaned = _cleanup.process(rawText);
    }

    cleaned = style.apply(cleaned);
    cleaned = DictionaryService.instance.applyReplacements(cleaned);

    if (cleaned.isNotEmpty) {
      final wordCount = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      await StatsService.instance.recordTranscription(wordCount: wordCount);
    }

    return cleaned;
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    _speech.stop();
    super.dispose();
  }
}
