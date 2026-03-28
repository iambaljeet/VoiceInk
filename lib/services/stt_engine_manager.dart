import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available STT provider types.
enum SttProvider {
  /// whisper.cpp CLI-based transcription. Needs whisper-cli binary + model download.
  whisperCpp,

  /// Sherpa-ONNX based transcription. Uses native Dart FFI. Supports 1600+ languages.
  sherpaOnnx,
}

extension SttProviderX on SttProvider {
  String get label {
    switch (this) {
      case SttProvider.whisperCpp:
        return 'Whisper.cpp';
      case SttProvider.sherpaOnnx:
        return 'Sherpa-ONNX';
    }
  }

  String get description {
    switch (this) {
      case SttProvider.whisperCpp:
        return 'High-quality offline transcription using whisper.cpp. Requires CLI binary.';
      case SttProvider.sherpaOnnx:
        return 'Cross-platform offline STT with native Dart FFI. 1600+ languages.';
    }
  }

  String get icon {
    switch (this) {
      case SttProvider.whisperCpp:
        return '🧠';
      case SttProvider.sherpaOnnx:
        return '🔊';
    }
  }
}

/// Manages STT provider selection and persistence.
class SttEngineManager extends ChangeNotifier {
  static const _prefKey = 'stt_provider';

  SttProvider _provider = SttProvider.whisperCpp;

  SttProvider get provider => _provider;

  /// For backward compatibility — alias for provider
  SttProvider get engine => _provider;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    // Also check legacy key for migration
    if (saved != null) {
      _provider = SttProvider.values.firstWhere(
        (p) => p.name == saved,
        orElse: () => SttProvider.whisperCpp,
      );
    } else {
      // Check legacy key
      final legacy = prefs.getString('stt_engine');
      if (legacy == 'model' || legacy == null) {
        _provider = SttProvider.whisperCpp;
      }
    }
    notifyListeners();
  }

  Future<void> setProvider(SttProvider provider) async {
    if (_provider == provider) return;
    _provider = provider;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, provider.name);
  }

  /// For backward compatibility
  Future<void> setEngine(SttProvider provider) => setProvider(provider);
}
