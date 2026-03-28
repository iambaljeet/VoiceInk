/// Sherpa-ONNX model definitions and download URLs.
///
/// Models are downloaded from HuggingFace. Each model has a type that
/// determines its architecture (whisper, sense_voice, moonshine, paraformer)
/// and a set of files to download.
class SherpaModel {
  final String id;
  final String name;
  final String description;
  final String modelType; // whisper, sense_voice, moonshine, paraformer
  final int sizeBytes;
  /// Map of filename → download URL for all model files.
  final Map<String, String> files;

  const SherpaModel({
    required this.id,
    required this.name,
    required this.description,
    required this.modelType,
    required this.sizeBytes,
    required this.files,
  });

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / (1024 * 1024)).round()} MB';
  }

  static const _hfBase = 'https://huggingface.co/csukuangfj';

  static const List<SherpaModel> available = [
    // ── Whisper ONNX ──
    SherpaModel(
      id: 'whisper-tiny',
      name: 'Whisper Tiny (ONNX)',
      description: 'Fastest. Good for quick dictation.',
      modelType: 'whisper',
      sizeBytes: 60000000,
      files: {
        'tiny-encoder.int8.onnx':
            '$_hfBase/sherpa-onnx-whisper-tiny/resolve/main/tiny-encoder.int8.onnx',
        'tiny-decoder.int8.onnx':
            '$_hfBase/sherpa-onnx-whisper-tiny/resolve/main/tiny-decoder.int8.onnx',
        'tiny-tokens.txt':
            '$_hfBase/sherpa-onnx-whisper-tiny/resolve/main/tiny-tokens.txt',
      },
    ),
    SherpaModel(
      id: 'whisper-base',
      name: 'Whisper Base (ONNX)',
      description: 'Good balance of speed and accuracy.',
      modelType: 'whisper',
      sizeBytes: 160000000,
      files: {
        'base-encoder.int8.onnx':
            '$_hfBase/sherpa-onnx-whisper-base/resolve/main/base-encoder.int8.onnx',
        'base-decoder.int8.onnx':
            '$_hfBase/sherpa-onnx-whisper-base/resolve/main/base-decoder.int8.onnx',
        'base-tokens.txt':
            '$_hfBase/sherpa-onnx-whisper-base/resolve/main/base-tokens.txt',
      },
    ),
    SherpaModel(
      id: 'whisper-small',
      name: 'Whisper Small (ONNX)',
      description: 'More accurate, good for multilingual.',
      modelType: 'whisper',
      sizeBytes: 490000000,
      files: {
        'small-encoder.int8.onnx':
            '$_hfBase/sherpa-onnx-whisper-small/resolve/main/small-encoder.int8.onnx',
        'small-decoder.int8.onnx':
            '$_hfBase/sherpa-onnx-whisper-small/resolve/main/small-decoder.int8.onnx',
        'small-tokens.txt':
            '$_hfBase/sherpa-onnx-whisper-small/resolve/main/small-tokens.txt',
      },
    ),
    SherpaModel(
      id: 'whisper-medium',
      name: 'Whisper Medium (ONNX)',
      description: 'High accuracy, needs more resources.',
      modelType: 'whisper',
      sizeBytes: 1500000000,
      files: {
        'medium-encoder.int8.onnx':
            '$_hfBase/sherpa-onnx-whisper-medium/resolve/main/medium-encoder.int8.onnx',
        'medium-decoder.int8.onnx':
            '$_hfBase/sherpa-onnx-whisper-medium/resolve/main/medium-decoder.int8.onnx',
        'medium-tokens.txt':
            '$_hfBase/sherpa-onnx-whisper-medium/resolve/main/medium-tokens.txt',
      },
    ),

    // ── SenseVoice ──
    SherpaModel(
      id: 'sense-voice',
      name: 'SenseVoice Small',
      description: 'Chinese/English/Japanese/Korean/Cantonese. Very fast.',
      modelType: 'sense_voice',
      sizeBytes: 230000000,
      files: {
        'model.int8.onnx':
            '$_hfBase/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx',
        'tokens.txt':
            '$_hfBase/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt',
      },
    ),

    // ── Moonshine (English, ultra-fast edge models) ──
    SherpaModel(
      id: 'moonshine-tiny',
      name: 'Moonshine Tiny',
      description: 'Ultra-fast English. Great for low-resource devices.',
      modelType: 'moonshine',
      sizeBytes: 70000000,
      files: {
        'preprocess.onnx':
            '$_hfBase/sherpa-onnx-moonshine-tiny-en-int8/resolve/main/preprocess.onnx',
        'encode.int8.onnx':
            '$_hfBase/sherpa-onnx-moonshine-tiny-en-int8/resolve/main/encode.int8.onnx',
        'uncached_decode.int8.onnx':
            '$_hfBase/sherpa-onnx-moonshine-tiny-en-int8/resolve/main/uncached_decode.int8.onnx',
        'cached_decode.int8.onnx':
            '$_hfBase/sherpa-onnx-moonshine-tiny-en-int8/resolve/main/cached_decode.int8.onnx',
        'tokens.txt':
            '$_hfBase/sherpa-onnx-moonshine-tiny-en-int8/resolve/main/tokens.txt',
      },
    ),
    SherpaModel(
      id: 'moonshine-base',
      name: 'Moonshine Base',
      description: 'Fast English with better accuracy than Tiny.',
      modelType: 'moonshine',
      sizeBytes: 290000000,
      files: {
        'preprocess.onnx':
            '$_hfBase/sherpa-onnx-moonshine-base-en-int8/resolve/main/preprocess.onnx',
        'encode.int8.onnx':
            '$_hfBase/sherpa-onnx-moonshine-base-en-int8/resolve/main/encode.int8.onnx',
        'uncached_decode.int8.onnx':
            '$_hfBase/sherpa-onnx-moonshine-base-en-int8/resolve/main/uncached_decode.int8.onnx',
        'cached_decode.int8.onnx':
            '$_hfBase/sherpa-onnx-moonshine-base-en-int8/resolve/main/cached_decode.int8.onnx',
        'tokens.txt':
            '$_hfBase/sherpa-onnx-moonshine-base-en-int8/resolve/main/tokens.txt',
      },
    ),

    // ── Paraformer (fast CTC-based models) ──
    SherpaModel(
      id: 'paraformer-en',
      name: 'Paraformer English',
      description: 'Fast English recognition. CTC-based architecture.',
      modelType: 'paraformer',
      sizeBytes: 220000000,
      files: {
        'model.onnx':
            '$_hfBase/sherpa-onnx-paraformer-en-2024-03-09/resolve/main/model.onnx',
        'tokens.txt':
            '$_hfBase/sherpa-onnx-paraformer-en-2024-03-09/resolve/main/tokens.txt',
      },
    ),
    SherpaModel(
      id: 'paraformer-trilingual',
      name: 'Paraformer Trilingual',
      description: 'Chinese, Cantonese & English. Fast inference.',
      modelType: 'paraformer',
      sizeBytes: 220000000,
      files: {
        'model.int8.onnx':
            '$_hfBase/sherpa-onnx-paraformer-trilingual-zh-cantonese-en/resolve/main/model.int8.onnx',
        'tokens.txt':
            '$_hfBase/sherpa-onnx-paraformer-trilingual-zh-cantonese-en/resolve/main/tokens.txt',
      },
    ),
  ];
}
