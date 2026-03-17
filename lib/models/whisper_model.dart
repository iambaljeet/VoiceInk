/// Whisper model definitions and download URLs
class WhisperModel {
  final String id;
  final String name;
  final String description;
  final int sizeBytes;
  final String downloadUrl;

  const WhisperModel({
    required this.id,
    required this.name,
    required this.description,
    required this.sizeBytes,
    required this.downloadUrl,
  });

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / (1024 * 1024)).round()} MB';
  }

  static const _baseUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

  static const List<WhisperModel> available = [
    WhisperModel(
      id: 'tiny.en',
      name: 'Tiny (English)',
      description: 'Fastest, least accurate. Good for quick notes.',
      sizeBytes: 77704715,
      downloadUrl: '$_baseUrl/ggml-tiny.en.bin',
    ),
    WhisperModel(
      id: 'tiny',
      name: 'Tiny (Multilingual)',
      description: 'Fastest multilingual model.',
      sizeBytes: 77691713,
      downloadUrl: '$_baseUrl/ggml-tiny.bin',
    ),
    WhisperModel(
      id: 'base.en',
      name: 'Base (English)',
      description: 'Good balance of speed and accuracy for English.',
      sizeBytes: 147964211,
      downloadUrl: '$_baseUrl/ggml-base.en.bin',
    ),
    WhisperModel(
      id: 'base',
      name: 'Base (Multilingual)',
      description: 'Good balance for multiple languages.',
      sizeBytes: 147951465,
      downloadUrl: '$_baseUrl/ggml-base.bin',
    ),
    WhisperModel(
      id: 'small.en',
      name: 'Small (English)',
      description: 'More accurate, slightly slower.',
      sizeBytes: 487614201,
      downloadUrl: '$_baseUrl/ggml-small.en.bin',
    ),
    WhisperModel(
      id: 'small',
      name: 'Small (Multilingual)',
      description: 'More accurate multilingual model.',
      sizeBytes: 487601967,
      downloadUrl: '$_baseUrl/ggml-small.bin',
    ),
    WhisperModel(
      id: 'medium.en',
      name: 'Medium (English)',
      description: 'High accuracy, requires more resources.',
      sizeBytes: 1533774781,
      downloadUrl: '$_baseUrl/ggml-medium.en.bin',
    ),
    WhisperModel(
      id: 'medium',
      name: 'Medium (Multilingual)',
      description: 'High accuracy multilingual.',
      sizeBytes: 1533763059,
      downloadUrl: '$_baseUrl/ggml-medium.bin',
    ),
    WhisperModel(
      id: 'large-v3-turbo',
      name: 'Large V3 Turbo',
      description: 'Best quality with optimized speed.',
      sizeBytes: 1624555275,
      downloadUrl: '$_baseUrl/ggml-large-v3-turbo.bin',
    ),
  ];
}
