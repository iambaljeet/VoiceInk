import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart' as wffi;

/// Cross-platform whisper transcription.
/// Desktop: uses whisper-cli subprocess.
/// Android/iOS: uses whisper_flutter_new FFI bindings.
class WhisperService {
  final String? cliPath;

  // Cached FFI instance — reused across transcriptions to avoid
  // repeated model load/unload which causes native crashes (SIGSEGV).
  wffi.Whisper? _cachedWhisper;
  String? _cachedModelPath;

  WhisperService([this.cliPath]);

  Future<String> transcribe({
    required String audioPath,
    required String modelPath,
    String language = 'en',
    int threads = 4,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return _transcribeFFI(audioPath, modelPath, threads);
    }
    if (cliPath == null) throw Exception('Whisper CLI path not set');
    return _transcribeCLI(audioPath, modelPath, language, threads);
  }

  Future<String> _transcribeCLI(
      String audioPath, String modelPath, String language, int threads) async {
    final result = await Process.run(
      cliPath!,
      [
        '-m', modelPath,
        '-f', audioPath,
        '--no-timestamps',
        '-l', language,
        '-t', '$threads',
        '--no-prints',
      ],
      environment: {
        'GGML_METAL_PATH_RESOURCES': File(cliPath!).parent.path,
      },
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => ProcessResult(-1, -1, '', 'Transcription timed out'),
    );

    if (result.exitCode != 0) {
      final stdout = result.stdout as String;
      if (stdout.trim().isNotEmpty) return _cleanOutput(stdout);
      throw Exception('Whisper failed (exit ${result.exitCode}): ${result.stderr}');
    }

    return _cleanOutput(result.stdout as String);
  }

  Future<String> _transcribeFFI(
      String audioPath, String modelPath, int threads) async {
    // Validate model file exists and has reasonable size before loading
    final modelFile = File(modelPath);
    if (!modelFile.existsSync()) {
      throw Exception('Model file not found: $modelPath');
    }
    final modelSize = modelFile.lengthSync();
    // All new-format models (whisper.cpp v1.8+) for base and above are > 140MB
    // Old-format base model was ~131MB. Reject obviously wrong files.
    if (modelSize < 50000000) {
      throw Exception('Model file too small ($modelSize bytes), likely corrupt. Please re-download.');
    }

    // Reuse cached Whisper instance if same model; avoids SIGSEGV from
    // repeated model load/unload cycles.
    if (_cachedWhisper == null || _cachedModelPath != modelPath) {
      final modelDir = File(modelPath).parent.path;
      final fileName = modelPath.split('/').last;
      final modelName = fileName.replaceAll('ggml-', '').replaceAll('.bin', '');
      final whisperModel = _toWhisperModel(modelName);

      debugPrint('[Whisper] Loading model: $modelName from $modelDir');
      _cachedWhisper = wffi.Whisper(
        model: whisperModel,
        modelDir: modelDir,
      );
      _cachedModelPath = modelPath;
    }

    final result = await _cachedWhisper!.transcribe(
      transcribeRequest: wffi.TranscribeRequest(
        audio: audioPath,
        isNoTimestamps: true,
        threads: threads,
      ),
    );

    return result.text.trim();
  }

  static wffi.WhisperModel _toWhisperModel(String name) {
    switch (name) {
      case 'tiny':
        return wffi.WhisperModel.tiny;
      case 'base':
        return wffi.WhisperModel.base;
      case 'small':
        return wffi.WhisperModel.small;
      case 'medium':
        return wffi.WhisperModel.medium;
      case 'large-v1':
        return wffi.WhisperModel.largeV1;
      case 'large-v2':
        return wffi.WhisperModel.largeV2;
      default:
        debugPrint('[Whisper] Unknown model "$name", falling back to base');
        return wffi.WhisperModel.base;
    }
  }

  String _cleanOutput(String raw) {
    return raw
        .split('\n')
        .where((line) {
          final t = line.trim();
          if (t.isEmpty) return false;
          if (t.startsWith('whisper_')) return false;
          if (t.startsWith('ggml_')) return false;
          if (t.startsWith('metal_')) return false;
          if (t.startsWith('main:')) return false;
          if (t.startsWith('system_info:')) return false;
          if (t.startsWith('output_')) return false;
          if (t.startsWith('[')) return false;
          return true;
        })
        .join(' ')
        .trim();
  }
}
