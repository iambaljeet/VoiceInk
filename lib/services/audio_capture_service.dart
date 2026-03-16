import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

/// Captures microphone audio and saves as WAV for whisper.cpp processing
class AudioCaptureService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _tempDir;
  String? _currentRecordingPath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  Future<void> init() async {
    final dir = await getTemporaryDirectory();
    _tempDir = dir.path;
  }

  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  /// Start recording audio from microphone
  Future<void> startRecording() async {
    if (_isRecording) return;

    final hasPerms = await _recorder.hasPermission();
    if (!hasPerms) {
      throw Exception('Microphone permission not granted');
    }

    _currentRecordingPath = '$_tempDir/voice_ink_recording.wav';

    // Clean up previous recording
    final prev = File(_currentRecordingPath!);
    if (await prev.exists()) await prev.delete();

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        numChannels: 1,
        sampleRate: 16000,
        bitRate: 256000,
      ),
      path: _currentRecordingPath!,
    );
    _isRecording = true;
  }

  /// Stop recording and return path to the WAV file
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    final path = await _recorder.stop();
    _isRecording = false;
    return path ?? _currentRecordingPath;
  }

  /// Cancel recording without saving
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    await _recorder.stop();
    _isRecording = false;

    if (_currentRecordingPath != null) {
      final file = File(_currentRecordingPath!);
      if (await file.exists()) await file.delete();
    }
  }

  void dispose() {
    _recorder.dispose();
  }
}
