import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'stt_transcriber.dart';
import 'sherpa_model_manager.dart';

/// Sherpa-ONNX based transcriber using native Dart FFI.
///
/// Supports Whisper ONNX and SenseVoice models for offline transcription.
/// Uses the sherpa_onnx package for direct native inference without CLI.
class SherpaOnnxTranscriber implements SttTranscriber {
  bool _initialized = false;
  sherpa.OfflineRecognizer? _recognizer;
  SherpaModelPaths? _loadedPaths;

  @override
  String get providerName => 'Sherpa-ONNX';

  @override
  bool get isAvailable => _initialized;

  @override
  Future<void> init() async {
    try {
      sherpa.initBindings();
      _initialized = true;
      final prefs = await SharedPreferences.getInstance();
      _language = prefs.getString('whisper_language') ?? 'auto';
      debugPrint('[SherpaOnnx] Bindings initialized, language=$_language');
    } catch (e) {
      debugPrint('[SherpaOnnx] Failed to initialize: $e');
      _initialized = false;
    }
  }

  /// Update language preference. Forces recognizer reload on next transcription.
  void setLanguage(String language) {
    if (_language != language) {
      _language = language;
      // Force recognizer rebuild with new language
      _recognizer?.free();
      _recognizer = null;
      _loadedPaths = null;
    }
  }

  /// Load or reload the recognizer with given model paths.
  void _ensureRecognizer(SherpaModelPaths paths) {
    if (_loadedPaths?.modelDir == paths.modelDir &&
        _loadedPaths?.modelType == paths.modelType &&
        _recognizer != null) {
      return;
    }

    // Free previous recognizer
    _recognizer?.free();

    final config = _buildConfig(paths);
    _recognizer = sherpa.OfflineRecognizer(config);
    _loadedPaths = paths;
    debugPrint('[SherpaOnnx] Recognizer loaded: ${paths.modelType}');
  }

  String _language = 'auto';

  sherpa.OfflineRecognizerConfig _buildConfig(SherpaModelPaths paths) {
    switch (paths.modelType) {
      case 'sense_voice':
        return sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            senseVoice: sherpa.OfflineSenseVoiceModelConfig(
              model: paths.fileMatching('model') ?? '',
              language: _language == 'auto' ? '' : _language,
            ),
            tokens: paths.tokens,
            numThreads: 4,
            debug: false,
            modelType: 'sense_voice',
          ),
        );

      case 'moonshine':
        return sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            moonshine: sherpa.OfflineMoonshineModelConfig(
              preprocessor: paths.fileMatching('preprocess') ?? '',
              encoder: paths.fileMatching('encode') ?? '',
              uncachedDecoder: paths.fileMatching('uncached_decode') ?? '',
              cachedDecoder: paths.fileMatching('cached_decode') ?? '',
            ),
            tokens: paths.tokens,
            numThreads: 4,
            debug: false,
            modelType: 'moonshine',
          ),
        );

      case 'paraformer':
        return sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            paraformer: sherpa.OfflineParaformerModelConfig(
              model: paths.fileMatching('model') ?? '',
            ),
            tokens: paths.tokens,
            numThreads: 4,
            debug: false,
            modelType: 'paraformer',
          ),
        );

      default: // whisper
        return sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            whisper: sherpa.OfflineWhisperModelConfig(
              encoder: paths.fileMatching('encoder') ?? '',
              decoder: paths.fileMatching('decoder') ?? '',
              language: _language == 'auto' ? '' : _language,
              task: 'transcribe',
            ),
            tokens: paths.tokens,
            numThreads: 4,
            debug: false,
            modelType: 'whisper',
          ),
        );
    }
  }

  @override
  Future<String> transcribe({
    required String audioPath,
    required String modelPath,
    String language = 'auto',
    int threads = 4,
  }) async {
    if (!_initialized) {
      throw Exception('Sherpa-ONNX bindings not initialized');
    }

    // modelPath is the directory containing the model files.
    // Parse the SherpaModelPaths from the directory.
    // For this transcriber, modelPath should be the encoder path,
    // and we derive the rest from the same directory.
    // However, since we need all paths, the caller should set up
    // the recognizer first via loadModel().

    if (_recognizer == null) {
      throw Exception('No model loaded. Call loadModel() first.');
    }

    return await compute(_transcribeIsolate, _TranscribeArgs(
      audioPath: audioPath,
      recognizer: null, // Can't send recognizer to isolate
    )).catchError((_) {
      // Fallback to main-thread transcription if isolate fails
      return _transcribeSync(audioPath);
    });
  }

  /// Synchronous transcription on the current thread.
  String _transcribeSync(String audioPath) {
    if (_recognizer == null) {
      throw Exception('No model loaded');
    }

    final wave = sherpa.readWave(audioPath);
    if (wave.samples.isEmpty) {
      return '';
    }

    final stream = _recognizer!.createStream();
    stream.acceptWaveform(
        samples: wave.samples, sampleRate: wave.sampleRate);
    _recognizer!.decode(stream);
    final result = _recognizer!.getResult(stream);
    stream.free();

    return result.text.trim();
  }

  /// Load a model for transcription.
  void loadModel(SherpaModelPaths paths) {
    if (!_initialized) {
      debugPrint('[SherpaOnnx] Cannot load model — bindings not initialized');
      return;
    }
    _ensureRecognizer(paths);
  }

  @override
  void dispose() {
    _recognizer?.free();
    _recognizer = null;
    _loadedPaths = null;
  }
}

class _TranscribeArgs {
  final String audioPath;
  final sherpa.OfflineRecognizer? recognizer;
  _TranscribeArgs({required this.audioPath, required this.recognizer});
}

String _transcribeIsolate(_TranscribeArgs args) {
  // Note: sherpa-onnx recognizer can't be passed to isolate.
  // This is a placeholder — actual transcription happens on main thread.
  throw UnimplementedError('Isolate transcription not supported');
}
