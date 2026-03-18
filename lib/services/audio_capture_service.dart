import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

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
        // Use 44100Hz — universally supported sample rate.
        // 16kHz is often not supported and produces silence.
        // Native code resamples to 16kHz for whisper.cpp.
        sampleRate: 44100,
        bitRate: 705600, // 44100 * 16 * 1
      ),
      path: path,
    );
    _isRecording = true;
    debugPrint('[AudioCapture] Started recording chunk $_chunkIndex → $path');
  }

  /// Stop current recording and return the WAV file path
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    final path = await _recorder.stop();
    _isRecording = false;
    final resultPath = path ?? _getChunkPath(_chunkIndex);
    
    // Diagnostic: log file details
    try {
      final file = File(resultPath);
      if (await file.exists()) {
        final size = await file.length();
        final bytes = await file.readAsBytes();
        final stats = _analyzeWav(bytes);
        debugPrint('[AudioCapture] Stopped chunk $_chunkIndex: $size bytes, $stats');
      } else {
        debugPrint('[AudioCapture] WARNING: chunk file does not exist: $resultPath');
      }
    } catch (e) {
      debugPrint('[AudioCapture] Diagnostics error: $e');
    }
    
    return resultPath;
  }

  /// Analyze WAV file and return diagnostic info
  String _analyzeWav(Uint8List bytes) {
    if (bytes.length < 44) return 'TOO_SHORT(${bytes.length})';
    
    // Read WAV header
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') {
      return 'NOT_WAV(magic=$riff/$wave)';
    }
    
    final bd = ByteData.sublistView(bytes);
    final channels = bd.getUint16(22, Endian.little);
    final sampleRate = bd.getUint32(24, Endian.little);
    final bitsPerSample = bd.getUint16(34, Endian.little);
    
    // Find data chunk
    int dataOffset = 36;
    int dataSize = 0;
    while (dataOffset + 8 < bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(dataOffset, dataOffset + 4));
      final chunkSize = bd.getUint32(dataOffset + 4, Endian.little);
      if (chunkId == 'data') {
        dataOffset += 8;
        dataSize = chunkSize;
        break;
      }
      dataOffset += 8 + chunkSize;
    }
    
    // Calculate RMS energy of audio data
    double rms = 0;
    int maxAbs = 0;
    if (bitsPerSample == 16 && dataOffset + dataSize <= bytes.length) {
      final numSamples = dataSize ~/ 2;
      double sumSquares = 0;
      for (int i = 0; i < numSamples && (dataOffset + i * 2 + 1) < bytes.length; i++) {
        final sample = bd.getInt16(dataOffset + i * 2, Endian.little);
        sumSquares += sample * sample;
        final abs = sample.abs();
        if (abs > maxAbs) maxAbs = abs;
      }
      rms = numSamples > 0 ? (sumSquares / numSamples) : 0;
      rms = rms > 0 ? (rms * 1.0).toDouble() : 0;
      // Convert to rough dB
      final rmsVal = numSamples > 0 ? (sumSquares / numSamples) : 0.0;
      final rmsAmplitude = rmsVal > 0 ? (rmsVal).toDouble() : 0.0;
      return 'WAV ch=$channels rate=$sampleRate bits=$bitsPerSample data=${dataSize}B samples=${dataSize ~/ 2} rmsEnergy=${rmsAmplitude.toStringAsFixed(0)} maxSample=$maxAbs ${maxAbs < 100 ? "⚠️SILENCE" : "✓HAS_AUDIO"}';
    }
    
    return 'WAV ch=$channels rate=$sampleRate bits=$bitsPerSample data=${dataSize}B';
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
