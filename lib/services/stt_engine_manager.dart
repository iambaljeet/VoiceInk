import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available STT engine types.
enum SttEngine {
  /// Platform native STT (Apple SFSpeechRecognizer / Google SpeechRecognizer).
  /// Zero download, instant, real-time. Quality depends on OS.
  native,

  /// AI model-based streaming (whisper.cpp on all platforms).
  /// Needs whisper model download. Higher quality, fully offline guaranteed.
  model,
}

extension SttEngineX on SttEngine {
  String get label {
    switch (this) {
      case SttEngine.native:
        return 'System Speech';
      case SttEngine.model:
        return 'AI Model (Whisper)';
    }
  }

  String get description {
    switch (this) {
      case SttEngine.native:
        return 'Uses built-in speech engine. No download needed. Real-time.';
      case SttEngine.model:
        return 'Uses whisper.cpp model. Download required. Higher quality.';
    }
  }

  String get icon {
    switch (this) {
      case SttEngine.native:
        return '🗣️';
      case SttEngine.model:
        return '🧠';
    }
  }
}

/// Manages STT engine selection and persistence.
class SttEngineManager extends ChangeNotifier {
  static const _prefKey = 'stt_engine';

  SttEngine _engine = SttEngine.native;
  bool _nativeAvailable = false;

  SttEngine get engine => _engine;
  bool get nativeAvailable => _nativeAvailable;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved == 'model') {
      _engine = SttEngine.model;
    } else {
      _engine = SttEngine.native;
    }
    notifyListeners();
  }

  void setNativeAvailable(bool available) {
    _nativeAvailable = available;
    notifyListeners();
  }

  Future<void> setEngine(SttEngine engine) async {
    if (_engine == engine) return;
    _engine = engine;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, engine.name);
  }
}
