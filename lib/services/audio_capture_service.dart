import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

/// Captures microphone audio for whisper.cpp processing.
/// Supports streaming mode: records in chunks for real-time transcription.
class AudioCaptureService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _tempDir;
  bool _isRecording = false;
  int _chunkIndex = 0;

  bool get isRecording => _isRecording;

  Future<void> init() async {
    final dir = await getTemporaryDirectory();
    _tempDir = '${dir.path}/voice_ink';
    await Directory(_tempDir!).create(recursive: true);
  }

  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  /// Start recording a single chunk
  Future<void> startRecording() async {
    if (_isRecording) return;

    final hasPerms = await _recorder.hasPermission();
    if (!hasPerms) {
      throw Exception('Microphone permission not granted');
    }

    _chunkIndex++;
    final path = _getChunkPath(_chunkIndex);

    // Clean up old file
    final prev = File(path);
    if (await prev.exists()) await prev.delete();

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        numChannels: 1,
        sampleRate: 16000,
        bitRate: 256000,
      ),
      path: path,
    );
    _isRecording = true;
  }

  /// Stop current recording and return the WAV file path
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    final path = await _recorder.stop();
    _isRecording = false;
    return path ?? _getChunkPath(_chunkIndex);
  }

  /// Cancel recording without saving
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    await _recorder.stop();
    _isRecording = false;
  }

  String _getChunkPath(int index) => '$_tempDir/chunk_$index.wav';

  /// Clean up all temp files
  Future<void> cleanup() async {
    if (_tempDir == null) return;
    final dir = Directory(_tempDir!);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.wav')) {
          try { await entity.delete(); } catch (_) {}
        }
      }
    }
  }

  void dispose() {
    _recorder.dispose();
  }
}
