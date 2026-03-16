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
    int? threads,
  }) async {
    final args = <String>[
      '-m', modelPath,
      '-f', audioPath,
      '--no-timestamps',
      '-l', language,
      '-t', '${threads ?? 4}',
      '--no-prints',
    ];

    if (translate) {
      args.add('--translate');
    }

    final result = await Process.run(
      _whisperBinaryPath,
      args,
      environment: {'GGML_METAL_PATH_RESOURCES': File(_whisperBinaryPath).parent.path},
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => ProcessResult(-1, -1, '', 'Transcription timed out'),
    );

    if (result.exitCode != 0) {
      final stderr = result.stderr as String;
      // If it just has Metal/ggml warnings but produced output, that's ok
      final stdout = result.stdout as String;
      if (stdout.trim().isNotEmpty) {
        return _cleanOutput(stdout);
      }
      throw Exception('Whisper failed (exit ${result.exitCode}): $stderr');
    }

    return _cleanOutput(result.stdout as String);
  }

  String _cleanOutput(String raw) {
    final lines = raw.split('\n');
    final textLines = lines.where((line) {
      final t = line.trim();
      if (t.isEmpty) return false;
      if (t.startsWith('whisper_')) return false;
      if (t.startsWith('ggml_')) return false;
      if (t.startsWith('metal_')) return false;
      if (t.startsWith('main:')) return false;
      if (t.startsWith('system_info:')) return false;
      if (t.startsWith('output_')) return false;
      if (t.startsWith('[')) return false; // timestamp lines
      return true;
    }).toList();
    return textLines.join(' ').trim();
  }
}
