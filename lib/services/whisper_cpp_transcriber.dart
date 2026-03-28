import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'stt_transcriber.dart';

/// Whisper.cpp-based transcriber using the whisper-cli subprocess.
///
/// Resolves the whisper-cli binary from standard locations and invokes
/// it as a subprocess for each transcription request.
class WhisperCppTranscriber implements SttTranscriber {
  String? _cliPath;

  @override
  String get providerName => 'Whisper.cpp';

  @override
  bool get isAvailable => _cliPath != null;

  String? get cliPath => _cliPath;

  @override
  Future<void> init() async {
    _cliPath = await _resolveCliPath();
    debugPrint('[WhisperCpp] CLI path: $_cliPath');
  }

  @override
  Future<String> transcribe({
    required String audioPath,
    required String modelPath,
    String language = 'auto',
    int threads = 4,
  }) async {
    if (_cliPath == null) {
      throw Exception('Whisper CLI binary not found');
    }

    final result = await Process.run(
      _cliPath!,
      [
        '-m', modelPath,
        '-f', audioPath,
        '--no-timestamps',
        '-l', language,
        '-t', '$threads',
        '--no-prints',
        '--no-speech-thold', '0.3',
      ],
      environment: Platform.isMacOS
          ? {'GGML_METAL_PATH_RESOURCES': File(_cliPath!).parent.path}
          : null,
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => ProcessResult(-1, -1, '', 'Transcription timed out'),
    );

    if (result.exitCode != 0) {
      final stdout = result.stdout as String;
      if (stdout.trim().isNotEmpty) return _cleanOutput(stdout);
      throw Exception(
          'Whisper failed (exit ${result.exitCode}): ${result.stderr}');
    }

    return _cleanOutput(result.stdout as String);
  }

  @override
  void dispose() {
    // No persistent resources to clean up for CLI-based transcription
  }

  /// Resolve whisper-cli binary from known locations.
  Future<String?> _resolveCliPath() async {
    final candidates = <String>[];

    if (Platform.isMacOS) {
      // App bundle Resources
      final exe = Platform.resolvedExecutable;
      final bundleBin = p.join(
          p.dirname(exe), '..', 'Resources', 'whisper.cpp', 'bin', 'whisper-cli');
      candidates.add(bundleBin);
      // Dev build location
      candidates.add(p.join(Directory.current.path,
          'native', 'whisper.cpp', 'build', 'bin', 'whisper-cli'));
    } else if (Platform.isWindows) {
      final exe = Platform.resolvedExecutable;
      final bundleBin =
          p.join(p.dirname(exe), 'data', 'whisper.cpp', 'bin', 'whisper-cli.exe');
      candidates.add(bundleBin);
      candidates.add(p.join(Directory.current.path,
          'native', 'whisper.cpp', 'build', 'bin', 'Release', 'whisper-cli.exe'));
      candidates.add(p.join(Directory.current.path,
          'native', 'whisper.cpp', 'build', 'bin', 'whisper-cli.exe'));
    }

    // Check PATH
    final pathBin = Platform.isWindows ? 'whisper-cli.exe' : 'whisper-cli';
    candidates.add(pathBin);

    for (final path in candidates) {
      if (path == pathBin) {
        // Check via `which`/`where`
        try {
          final which =
              Platform.isWindows ? 'where' : 'which';
          final result = await Process.run(which, [pathBin]);
          if (result.exitCode == 0) {
            return (result.stdout as String).trim().split('\n').first;
          }
        } catch (_) {}
      } else if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  /// Clean whisper-cli output by removing debug lines.
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
