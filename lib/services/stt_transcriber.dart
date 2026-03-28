/// Abstract interface for speech-to-text transcription backends.
///
/// Each provider (whisper.cpp, sherpa-onnx, etc.) implements this interface
/// to provide a unified transcription API for the streaming/dictation services.
abstract class SttTranscriber {
  /// Initialize the transcriber (resolve binaries, load models, etc.)
  Future<void> init();

  /// Transcribe an audio file to text.
  ///
  /// [audioPath] — Path to a WAV file (16kHz, mono, 16-bit PCM).
  /// [modelPath] — Path to the model file/directory.
  /// [language] — Language code ('en', 'hi', 'auto', etc.)
  /// [threads] — Number of CPU threads to use.
  Future<String> transcribe({
    required String audioPath,
    required String modelPath,
    String language = 'auto',
    int threads = 4,
  });

  /// Whether this transcriber is ready to use (binary/model available).
  bool get isAvailable;

  /// Human-readable name for logging/UI.
  String get providerName;

  /// Clean up resources.
  void dispose();
}
