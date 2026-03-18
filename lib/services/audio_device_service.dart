import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages audio input device selection and provides mic level monitoring.
class AudioDeviceService extends ChangeNotifier {
  static const _prefDeviceId = 'mic_device_id';

  final AudioRecorder _testRecorder = AudioRecorder();

  List<InputDevice> _devices = [];
  InputDevice? _selectedDevice;
  double _level = 0.0;
  bool _testing = false;
  StreamSubscription? _testSub;

  List<InputDevice> get devices => _devices;
  InputDevice? get selectedDevice => _selectedDevice;
  double get level => _level;
  bool get isTesting => _testing;

  Future<void> init() async {
    await refreshDevices();
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefDeviceId);
    if (savedId != null) {
      final match = _devices.where((d) => d.id == savedId);
      if (match.isNotEmpty) {
        _selectedDevice = match.first;
      }
    }
  }

  Future<void> refreshDevices() async {
    try {
      _devices = await _testRecorder.listInputDevices();
      debugPrint('[AudioDevice] Found ${_devices.length} input devices');
    } catch (e) {
      debugPrint('[AudioDevice] List devices error: $e');
      _devices = [];
    }
    notifyListeners();
  }

  Future<void> selectDevice(InputDevice? device) async {
    _selectedDevice = device;
    final prefs = await SharedPreferences.getInstance();
    if (device != null) {
      await prefs.setString(_prefDeviceId, device.id);
    } else {
      await prefs.remove(_prefDeviceId);
    }
    notifyListeners();
  }

  /// Start streaming mic audio and calculating level for the visual meter.
  Future<void> startMicTest() async {
    if (_testing) return;
    _testing = true;
    _level = 0;
    notifyListeners();

    try {
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        device: _selectedDevice,
      );
      final stream = await _testRecorder.startStream(config);
      _testSub = stream.listen((data) {
        final bytes = Uint8List.fromList(data);
        final bd = ByteData.view(bytes.buffer);
        final n = bytes.length ~/ 2;
        double sum = 0;
        for (int i = 0; i < n; i++) {
          final s = bd.getInt16(i * 2, Endian.little) / 32768.0;
          sum += s * s;
        }
        final rms = n > 0 ? sqrt(sum / n) : 0.0;
        _level = (rms * 8).clamp(0.0, 1.0);
        notifyListeners();
      });
    } catch (e) {
      debugPrint('[AudioDevice] Mic test error: $e');
      _testing = false;
      notifyListeners();
    }
  }

  /// Stop the mic test.
  Future<void> stopMicTest() async {
    await _testSub?.cancel();
    _testSub = null;
    try {
      await _testRecorder.stop();
    } catch (_) {}
    _testing = false;
    _level = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _testSub?.cancel();
    _testRecorder.dispose();
    super.dispose();
  }
}
