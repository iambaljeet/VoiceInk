import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'text_cleanup_service.dart';
import 'text_injection_service.dart';
import 'model_manager.dart';
import 'stt_transcriber.dart';
import 'whisper_cpp_transcriber.dart';
import 'dictionary_service.dart';
import 'stats_service.dart';
import '../models/writing_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real-time streaming STT using whisper.cpp with sliding window approach.
///
/// Architecture:
///  - Records 16 kHz mono PCM audio continuously via mic
///  - Maintains an append-only audio buffer with a commit cursor
///  - Periodically transcribes pending audio for partial preview
///  - Uses VAD to detect silence endpoints → commits text, advances cursor
///  - On stop: transcribes all remaining audio and commits
///  - Zero audio loss: new audio arriving during transcription is preserved
class WhisperStreamingService extends ChangeNotifier {
  final TextCleanupService _cleanup = TextCleanupService();
  final TextInjectionService _injection = TextInjectionService();
  final AudioRecorder _recorder = AudioRecorder();
  final ModelManager modelManager;
  SttTranscriber? _transcriber;

  // Sliding window parameters
  static const int _sampleRate = 16000;
  static const int _stepMs = 1500;      // Transcription interval
  static const int _windowMs = 30000;   // Preview transcribes last 30s max
  static const int _windowSamples = _sampleRate * _windowMs ~/ 1000;

  // VAD parameters
  static const double _vadThreshold = 0.004; // RMS below this = silence
  static const int _endpointSilenceMs = 2000; // 2s silence = commit endpoint

  // Audio state
  StreamSubscription? _audioSubscription;
  final List<double> _audioBuffer = [];
  String? _tempDir;
  String _language = 'auto';

  // Commit tracking — index up to which audio has been committed as text
  int _commitPos = 0;

  // Transcription state
  bool _isRecording = false;
  String _currentText = '';
  String _committedText = '';
  String? _errorMessage;
  bool _transcribing = false;

  // VAD state
  int _silentMs = 0;
  bool _speechDetected = false; // any speech since last commit
  double _smoothedEnergy = 0.0; // exponential moving average of RMS

  // Periodic transcription timer
  Timer? _transcribeTimer;

  bool get isRecording => _isRecording;
  String get currentText => _committedText + _currentText;
  String? get errorMessage => _errorMessage;

  WhisperStreamingService({required this.modelManager, SttTranscriber? transcriber})
      : _transcriber = transcriber;

  Future<void> init() async {
    final dir = await getTemporaryDirectory();
    _tempDir = p.join(dir.path, 'voice_ink_streaming');
    await Directory(_tempDir!).create(recursive: true);
    // If no transcriber was injected, create a default WhisperCppTranscriber
    if (_transcriber == null) {
      final wt = WhisperCppTranscriber();
      await wt.init();
      _transcriber = wt;
    }
    // Load saved language preference
    final prefs = await SharedPreferences.getInstance();
    _language = prefs.getString('whisper_language') ?? 'auto';
  }

  /// Replace the transcriber at runtime (e.g., when switching providers).
  void setTranscriber(SttTranscriber transcriber) {
    _transcriber = transcriber;
    notifyListeners();
  }

  bool get isWhisperAvailable => _transcriber?.isAvailable ?? false;

  /// Start recording. Optionally pass a specific [device] for the mic input.
  Future<void> startRecording({InputDevice? device}) async {
    if (_isRecording) return;
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

    if (!await _recorder.hasPermission()) {
      _errorMessage = 'Microphone permission not granted';
      notifyListeners();
      return;
    }

    _audioBuffer.clear();
    _commitPos = 0;
    _currentText = '';
    _committedText = '';
    _silentMs = 0;
    _speechDetected = false;
    _smoothedEnergy = 0.0;

    try {
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        device: device,
      );

      final audioStream = await _recorder.startStream(config);
      _audioSubscription = audioStream.listen(
        _onAudioData,
        onError: (e) {
          debugPrint('[WhisperStream] Audio error: $e');
          _errorMessage = 'Audio error: $e';
          notifyListeners();
        },
      );

      // Periodic transcription every step interval
      _transcribeTimer = Timer.periodic(
        const Duration(milliseconds: _stepMs),
        (_) => _onStep(),
      );

      _isRecording = true;
      notifyListeners();
      debugPrint('[WhisperStream] Recording started (window=${_windowMs}ms step=${_stepMs}ms)');
    } catch (e) {
      _errorMessage = 'Failed to start: $e';
      _isRecording = false;
      notifyListeners();
    }
  }

  void _onAudioData(List<int> data) {
    final bytes = Uint8List.fromList(data);
    final bd = ByteData.view(bytes.buffer);
    final numSamples = bytes.length ~/ 2;

    // Decode and buffer samples, compute RMS for VAD
    double sumSquares = 0;
    for (int i = 0; i < numSamples; i++) {
      final sample = bd.getInt16(i * 2, Endian.little) / 32768.0;
      _audioBuffer.add(sample);
      sumSquares += sample * sample;
    }

    final rms = numSamples > 0 ? sqrt(sumSquares / numSamples) : 0.0;
    final chunkDurationMs = (numSamples * 1000) ~/ _sampleRate;

    // Smoothed energy (exponential moving average) for robust VAD
    _smoothedEnergy = 0.6 * _smoothedEnergy + 0.4 * rms;

    if (_smoothedEnergy < _vadThreshold) {
      _silentMs += chunkDurationMs;
    } else {
      _silentMs = 0;
      _speechDetected = true;
    }

    // Endpoint: speech was detected and now silence for > threshold
    // Require meaningful audio beyond the commit position
    final pendingSamples = _audioBuffer.length - _commitPos;
    if (_speechDetected &&
        _silentMs >= _endpointSilenceMs &&
        pendingSamples > _sampleRate ~/ 2) {
      _onEndpoint();
    }
  }

  /// Called every STEP_MS — transcribe pending audio for partial preview
  Future<void> _onStep() async {
    if (_transcribing) return;
    final pendingSamples = _audioBuffer.length - _commitPos;
    if (pendingSamples < _sampleRate ~/ 4) return; // need at least 0.25s

    _transcribing = true;
    try {
      // Transcribe pending audio (from commit position to end), capped at window
      final start = max(_commitPos, _audioBuffer.length - _windowSamples);
      final windowSamples = Float32List.fromList(
        _audioBuffer.sublist(start),
      );

      final wavPath = p.join(_tempDir!, 'partial.wav');
      await _writeWav(wavPath, windowSamples, _sampleRate);

      final rawText = await _transcriber!.transcribe(
        audioPath: wavPath,
        modelPath: modelManager.selectedModelPath!,
        language: _language,
      );

      final trimmed = rawText.trim();
      if (trimmed.isNotEmpty &&
          !trimmed.contains('[BLANK_AUDIO]') &&
          !trimmed.contains('[BLANK AUDIO]')) {
        _currentText = trimmed;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[WhisperStream] Partial transcription error: $e');
    } finally {
      _transcribing = false;
    }
  }

  /// Endpoint detected — commit pending text, advance cursor, preserve new audio
  Future<void> _onEndpoint() async {
    final pendingSamples = _audioBuffer.length - _commitPos;
    if (pendingSamples < _sampleRate ~/ 4) return;

    debugPrint('[WhisperStream] Endpoint detected — committing ${pendingSamples ~/ _sampleRate}s of audio');
    _speechDetected = false;
    _silentMs = 0;

    // Wait for any in-progress transcription to finish
    while (_transcribing) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _transcribing = true;
    try {
      // Snapshot: transcribe audio from commit position to current end
      // New audio may arrive during transcription — it's preserved automatically
      // because we only advance _commitPos, never clear the buffer mid-flight.
      final snapshotEnd = _audioBuffer.length;
      final pendingAudio = _audioBuffer.sublist(_commitPos, snapshotEnd);

      // Trim trailing silence (prevents whisper hallucinations from silence)
      final trimmed = _trimTrailingSilence(pendingAudio);
      if (trimmed.length < _sampleRate ~/ 4) {
        // Too short after trimming — skip but advance cursor
        _commitPos = snapshotEnd;
        _currentText = '';
        _compactBuffer();
        notifyListeners();
        return;
      }

      final samples = Float32List.fromList(trimmed);
      final wavPath = p.join(_tempDir!, 'endpoint.wav');
      await _writeWav(wavPath, samples, _sampleRate);

      final rawText = await _transcriber!.transcribe(
        audioPath: wavPath,
        modelPath: modelManager.selectedModelPath!,
        language: _language,
      );

      final text = rawText.trim();
      if (text.isNotEmpty &&
          !text.contains('[BLANK_AUDIO]') &&
          !text.contains('[BLANK AUDIO]')) {
        final cleaned = await _postProcess(text);
        if (cleaned.isNotEmpty) {
          _committedText += '$cleaned ';
          _injection.injectText('$cleaned ');
        }
      }

      // Advance commit cursor to snapshot point
      // Audio that arrived DURING transcription stays in the buffer
      _commitPos = snapshotEnd;
      _currentText = '';
      _compactBuffer();
      notifyListeners();
    } catch (e) {
      debugPrint('[WhisperStream] Endpoint transcription error: $e');
    } finally {
      _transcribing = false;
    }
  }

  /// Remove committed audio from the buffer to prevent unbounded growth.
  /// Adjusts _commitPos accordingly.
  void _compactBuffer() {
    if (_commitPos > _sampleRate * 5) {
      // Keep a small safety margin (0.5s) before commit pos for edge cases
      final removeCount = _commitPos - (_sampleRate ~/ 2);
      if (removeCount > 0) {
        _audioBuffer.removeRange(0, removeCount);
        _commitPos -= removeCount;
      }
    }
  }

  /// Trim trailing silence from audio samples (prevents whisper hallucinations).
  List<double> _trimTrailingSilence(List<double> buffer) {
    int end = buffer.length;
    const chunkSize = 1600; // 100ms at 16kHz
    while (end > chunkSize) {
      double sum = 0;
      for (int i = end - chunkSize; i < end; i++) {
        sum += buffer[i] * buffer[i];
      }
      final rms = sqrt(sum / chunkSize);
      if (rms > _vadThreshold) break;
      end -= chunkSize;
    }
    // Add a small tail (250ms) for word endings
    end = min(buffer.length, end + _sampleRate ~/ 4);
    return buffer.sublist(0, end);
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _transcribeTimer?.cancel();
    _transcribeTimer = null;

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop();

    // Wait for any in-progress transcription (endpoint or step) to finish
    while (_transcribing) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Final transcription of all audio beyond commit position
    final pendingSamples = _audioBuffer.length - _commitPos;
    if (pendingSamples > _sampleRate ~/ 4) {
      _transcribing = true;
      try {
        final pendingAudio = _audioBuffer.sublist(_commitPos);
        final trimmed = _trimTrailingSilence(pendingAudio);
        if (trimmed.length > _sampleRate ~/ 4) {
          final samples = Float32List.fromList(trimmed);
          final wavPath = p.join(_tempDir!, 'final.wav');
          await _writeWav(wavPath, samples, _sampleRate);

          final rawText = await _transcriber!.transcribe(
            audioPath: wavPath,
            modelPath: modelManager.selectedModelPath!,
            language: _language,
          );

          final text = rawText.trim();
          if (text.isNotEmpty &&
              !text.contains('[BLANK_AUDIO]') &&
              !text.contains('[BLANK AUDIO]')) {
            final cleaned = await _postProcess(text);
            if (cleaned.isNotEmpty) {
              _committedText += '$cleaned ';
              _injection.injectText('$cleaned ');
            }
          }
        }
      } catch (e) {
        debugPrint('[WhisperStream] Final transcription error: $e');
      } finally {
        _transcribing = false;
      }
    }

    _audioBuffer.clear();
    _commitPos = 0;
    _isRecording = false;
    _currentText = '';
    notifyListeners();
    debugPrint('[WhisperStream] Recording stopped');
  }

  Future<void> toggleRecording() async {
    if (_isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  /// Write Float32 samples to a 16-bit PCM WAV file
  Future<void> _writeWav(String path, Float32List samples, int sampleRate) async {
    final numSamples = samples.length;
    final dataSize = numSamples * 2;
    final fileSize = 44 + dataSize;

    final buffer = ByteData(fileSize);

    // RIFF header
    _writeAscii(buffer, 0, 'RIFF');
    buffer.setUint32(4, fileSize - 8, Endian.little);
    _writeAscii(buffer, 8, 'WAVE');

    // fmt chunk
    _writeAscii(buffer, 12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little);            // chunk size
    buffer.setUint16(20, 1, Endian.little);             // PCM format
    buffer.setUint16(22, 1, Endian.little);             // mono
    buffer.setUint32(24, sampleRate, Endian.little);    // sample rate
    buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    buffer.setUint16(32, 2, Endian.little);             // block align
    buffer.setUint16(34, 16, Endian.little);            // bits per sample

    // data chunk
    _writeAscii(buffer, 36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);

    int offset = 44;
    for (int i = 0; i < numSamples; i++) {
      final clamped = (samples[i] * 32767).round().clamp(-32768, 32767);
      buffer.setInt16(offset, clamped, Endian.little);
      offset += 2;
    }

    await File(path).writeAsBytes(buffer.buffer.asUint8List());
  }

  void _writeAscii(ByteData bd, int offset, String text) {
    for (int i = 0; i < text.length; i++) {
      bd.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  TextCleanupService get cleanup => _cleanup;

  /// Shared post-processing: cleanup → writing style → dictionary → stats
  Future<String> _postProcess(String rawText) async {
    // Load current writing style from preferences
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

    // Record stats
    if (cleaned.isNotEmpty) {
      final wordCount = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      await StatsService.instance.recordTranscription(wordCount: wordCount);
    }

    return cleaned;
  }

  @override
  void dispose() {
    _transcribeTimer?.cancel();
    _audioSubscription?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
