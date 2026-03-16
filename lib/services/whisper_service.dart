import 'dart:io';

/// Runs whisper.cpp CLI to transcribe audio files
class WhisperService {
  final String _whisperBinaryPath;

  WhisperService(this._whisperBinaryPath);

  /// Transcribe a WAV audio file using the specified model
  Future<String> transcribe({
    required String audioPath,
    required String modelPath,
    String language = 'en',
    bool translate = false,
  }) async {
    final args = [
      '-m', modelPath,
      '-f', audioPath,
      '--no-timestamps',
      '-nt', // no timestamps text
      '-l', language,
      '--print-special', 'false',
    ];

    if (translate) {
      args.add('--translate');
    }

    final result = await Process.run(_whisperBinaryPath, args);

    if (result.exitCode != 0) {
      throw Exception(
        'Whisper transcription failed: ${result.stderr}',
      );
    }

    // Parse output - whisper prints the text to stdout
    // Filter out log lines (those starting with whisper_, ggml_, metal_, main:, system_info)
    final lines = (result.stdout as String).split('\n');
    final textLines = lines.where((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return false;
      if (trimmed.startsWith('whisper_')) return false;
      if (trimmed.startsWith('ggml_')) return false;
      if (trimmed.startsWith('metal_')) return false;
      if (trimmed.startsWith('main:')) return false;
      if (trimmed.startsWith('system_info:')) return false;
      if (trimmed.startsWith('output_')) return false;
      return true;
    }).toList();

    return textLines.join(' ').trim();
  }
}
