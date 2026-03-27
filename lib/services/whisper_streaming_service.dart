import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'text_cleanup_service.dart';
import 'text_injection_service.dart';
import 'model_manager.dart';
import 'whisper_service.dart';
import 'dictionary_service.dart';
import 'stats_service.dart';
import '../models/writing_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real-time streaming STT using whisper.cpp with sliding window approach.
///
/// Architecture (matching whisper.cpp stream example):
///  - Records 16 kHz mono PCM audio continuously via mic
///  - Uses a sliding window: WINDOW_MS total, STEP_MS new audio, KEEP_MS overlap
///  - Transcribes at each step for near-real-time partial results
///  - Uses VAD (voice activity detection) to detect endpoints
///  - Commits text on endpoint (silence), resets buffer, continues
class WhisperStreamingService extends ChangeNotifier {
  final TextCleanupService _cleanup = TextCleanupService();
  final TextInjectionService _injection = TextInjectionService();
  final AudioRecorder _recorder = AudioRecorder();
  final ModelManager modelManager;
  WhisperService? _whisper;

  // Sliding window parameters (matching whisper.cpp stream defaults)
  static const int _sampleRate = 16000;
  static const int _stepMs = 1500;      // Process every 1.5s for responsiveness
  static const int _windowMs = 10000;   // Transcribe last 10s of audio
  static const int _keepMs = 1000;      // 1s overlap between segments for continuity

  static const int _windowSamples = _sampleRate * _windowMs ~/ 1000;
  static const int _keepSamples = _sampleRate * _keepMs ~/ 1000;

  // VAD parameters
  static const double _vadThreshold = 0.008; // RMS below this = silence
  static const int _endpointSilenceMs = 2000; // 2s silence = commit endpoint

  // Audio state
  StreamSubscription? _audioSubscription;
  final List<double> _audioBuffer = [];
  String? _tempDir;

  // Transcription state
  bool _isRecording = false;
  String _currentText = '';
  String _committedText = '';
  String? _errorMessage;
  bool _transcribing = false;

  // VAD state
  int _silentMs = 0;
  bool _speechStarted = false;

  // Periodic transcription timer
  Timer? _transcribeTimer;

  bool get isRecording => _isRecording;
  String get currentText => _committedText + _currentText;
  String? get errorMessage => _errorMessage;

  WhisperStreamingService({required this.modelManager});

  Future<void> init() async {
    final dir = await getTemporaryDirectory();
    _tempDir = '${dir.path}/voice_ink_streaming';
    await Directory(_tempDir!).create(recursive: true);
    _whisper = await _resolveWhisper();
  }

  Future<WhisperService?> _resolveWhisper() async {
    final execPath = Platform.resolvedExecutable;
    final appDir = File(execPath).parent.path;
    final ext = Platform.isWindows ? '.exe' : '';

    final candidates = [
      '$appDir/../Resources/whisper-cli$ext',
      '$appDir/whisper-cli$ext',
    ];
    candidates.add('${Directory.current.path}/native/whisper.cpp/build/bin/whisper-cli$ext');

    for (final path in candidates) {
      if (await File(path).exists()) return WhisperService(path);
    }

    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(cmd, ['whisper-cli']);
      if (result.exitCode == 0) {
        return WhisperService((result.stdout as String).trim());
      }
    } catch (_) {}

    return null;
  }

  bool get isWhisperAvailable => _whisper != null;

  /// Start recording. Optionally pass a specific [device] for the mic input.
  Future<void> startRecording({InputDevice? device}) async {
    if (_isRecording) return;
    _errorMessage = null;

    if (_whisper == null) {
      _errorMessage = 'Whisper not available. Check installation.';
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
    _currentText = '';
    _committedText = '';
    _silentMs = 0;
    _speechStarted = false;

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
      debugPrint('[WhisperStream] Recording started (window=${_windowMs}ms step=${_stepMs}ms keep=${_keepMs}ms)');
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

    // Calculate RMS for VAD
    double sumSquares = 0;
    for (int i = 0; i < numSamples; i++) {
      final sample = bd.getInt16(i * 2, Endian.little) / 32768.0;
      _audioBuffer.add(sample);
      sumSquares += sample * sample;
    }

    final rms = numSamples > 0 ? sqrt(sumSquares / numSamples) : 0.0;
    final chunkDurationMs = (numSamples * 1000) ~/ _sampleRate;

    if (rms < _vadThreshold) {
      _silentMs += chunkDurationMs;
    } else {
      _silentMs = 0;
      _speechStarted = true;
    }

    // Endpoint: speech was detected and now silence for > threshold
    if (_speechStarted &&
        _silentMs >= _endpointSilenceMs &&
        _audioBuffer.length > _sampleRate) {
      _onEndpoint();
    }
  }

  /// Called every STEP_MS — transcribe the sliding window for partial results
  Future<void> _onStep() async {
    if (_transcribing) return;
    if (_audioBuffer.length < _sampleRate ~/ 2) return; // need at least 0.5s
    if (!_speechStarted) return; // don't transcribe pure silence

    _transcribing = true;
    try {
      // Build the sliding window: last WINDOW_SAMPLES, or all if shorter
      final windowStart = max(0, _audioBuffer.length - _windowSamples);
      final windowSamples = Float32List.fromList(
        _audioBuffer.sublist(windowStart),
      );

      final wavPath = '$_tempDir/partial.wav';
      await _writeWav(wavPath, windowSamples, _sampleRate);

      final rawText = await _whisper!.transcribe(
        audioPath: wavPath,
        modelPath: modelManager.selectedModelPath!,
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

  /// Endpoint detected — commit current text, reset buffer
  Future<void> _onEndpoint() async {
    if (_audioBuffer.length < _sampleRate ~/ 2) return;

    debugPrint('[WhisperStream] Endpoint detected — committing');
    _speechStarted = false;
    _silentMs = 0;

    // Wait for any in-progress transcription to finish
    while (_transcribing) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _transcribing = true;
    try {
      // Trim trailing silence for cleaner transcription
      final trimmedBuffer = _trimSilence(_audioBuffer);
      if (trimmedBuffer.length < _sampleRate ~/ 4) {
        _audioBuffer.clear();
        _currentText = '';
        notifyListeners();
        return;
      }

      final samples = Float32List.fromList(trimmedBuffer);
      final wavPath = '$_tempDir/endpoint.wav';
      await _writeWav(wavPath, samples, _sampleRate);

      final rawText = await _whisper!.transcribe(
        audioPath: wavPath,
        modelPath: modelManager.selectedModelPath!,
      );

      final trimmed = rawText.trim();
      if (trimmed.isNotEmpty &&
          !trimmed.contains('[BLANK_AUDIO]') &&
          !trimmed.contains('[BLANK AUDIO]')) {
        final cleaned = await _postProcess(trimmed);
        if (cleaned.isNotEmpty) {
          _committedText += '$cleaned ';
          _injection.injectText('$cleaned ');
        }
      }

      // Keep a small overlap for context in next segment
      if (_audioBuffer.length > _keepSamples) {
        final keep = _audioBuffer.sublist(_audioBuffer.length - _keepSamples);
        _audioBuffer
          ..clear()
          ..addAll(keep);
      } else {
        _audioBuffer.clear();
      }
      _currentText = '';
      notifyListeners();
    } catch (e) {
      debugPrint('[WhisperStream] Endpoint transcription error: $e');
    } finally {
      _transcribing = false;
    }
  }

  /// Trim trailing silence from audio buffer
  List<double> _trimSilence(List<double> buffer) {
    // Find last non-silent sample (scanning backwards)
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
    // Add a small tail for context
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

    // Final transcription of remaining audio
    if (_audioBuffer.length > _sampleRate ~/ 2 && _speechStarted) {
      _transcribing = true;
      try {
        final trimmedBuffer = _trimSilence(_audioBuffer);
        if (trimmedBuffer.length > _sampleRate ~/ 4) {
          final samples = Float32List.fromList(trimmedBuffer);
          final wavPath = '$_tempDir/final.wav';
          await _writeWav(wavPath, samples, _sampleRate);

          final rawText = await _whisper!.transcribe(
            audioPath: wavPath,
            modelPath: modelManager.selectedModelPath!,
          );

          final trimmed = rawText.trim();
          if (trimmed.isNotEmpty &&
              !trimmed.contains('[BLANK_AUDIO]') &&
              !trimmed.contains('[BLANK AUDIO]')) {
            final cleaned = await _postProcess(trimmed);
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
