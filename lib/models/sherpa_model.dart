/// Sherpa-ONNX model definitions and download URLs.
///
/// Each model consists of an encoder, decoder, and tokens file.
/// Models are downloaded from HuggingFace as individual files.
class SherpaModel {
  final String id;
  final String name;
  final String description;
  final int sizeBytes;
  final String encoderUrl;
  final String decoderUrl;
  final String tokensUrl;
  final String encoderFilename;
  final String decoderFilename;
  final String tokensFilename;

  const SherpaModel({
    required this.id,
    required this.name,
    required this.description,
    required this.sizeBytes,
    required this.encoderUrl,
    required this.decoderUrl,
    required this.tokensUrl,
    required this.encoderFilename,
    required this.decoderFilename,
    required this.tokensFilename,
  });

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / (1024 * 1024)).round()} MB';
  }

  static const _hfBase = 'https://huggingface.co/csukuangfj';

  static const List<SherpaModel> available = [
    SherpaModel(
      id: 'whisper-tiny',
      name: 'Whisper Tiny (ONNX)',
      description: 'Fastest. Good for quick dictation.',
      sizeBytes: 60000000,
      encoderUrl:
          '$_hfBase/sherpa-onnx-whisper-tiny/resolve/main/tiny-encoder.int8.onnx',
      decoderUrl:
          '$_hfBase/sherpa-onnx-whisper-tiny/resolve/main/tiny-decoder.int8.onnx',
      tokensUrl:
          '$_hfBase/sherpa-onnx-whisper-tiny/resolve/main/tiny-tokens.txt',
      encoderFilename: 'tiny-encoder.int8.onnx',
      decoderFilename: 'tiny-decoder.int8.onnx',
      tokensFilename: 'tiny-tokens.txt',
    ),
    SherpaModel(
      id: 'whisper-base',
      name: 'Whisper Base (ONNX)',
      description: 'Good balance of speed and accuracy.',
      sizeBytes: 160000000,
      encoderUrl:
          '$_hfBase/sherpa-onnx-whisper-base/resolve/main/base-encoder.int8.onnx',
      decoderUrl:
          '$_hfBase/sherpa-onnx-whisper-base/resolve/main/base-decoder.int8.onnx',
      tokensUrl:
          '$_hfBase/sherpa-onnx-whisper-base/resolve/main/base-tokens.txt',
      encoderFilename: 'base-encoder.int8.onnx',
      decoderFilename: 'base-decoder.int8.onnx',
      tokensFilename: 'base-tokens.txt',
    ),
    SherpaModel(
      id: 'whisper-small',
      name: 'Whisper Small (ONNX)',
      description: 'More accurate, good for multilingual.',
      sizeBytes: 490000000,
      encoderUrl:
          '$_hfBase/sherpa-onnx-whisper-small/resolve/main/small-encoder.int8.onnx',
      decoderUrl:
          '$_hfBase/sherpa-onnx-whisper-small/resolve/main/small-decoder.int8.onnx',
      tokensUrl:
          '$_hfBase/sherpa-onnx-whisper-small/resolve/main/small-tokens.txt',
      encoderFilename: 'small-encoder.int8.onnx',
      decoderFilename: 'small-decoder.int8.onnx',
      tokensFilename: 'small-tokens.txt',
    ),
    SherpaModel(
      id: 'whisper-medium',
      name: 'Whisper Medium (ONNX)',
      description: 'High accuracy, needs more resources.',
      sizeBytes: 1500000000,
      encoderUrl:
          '$_hfBase/sherpa-onnx-whisper-medium/resolve/main/medium-encoder.int8.onnx',
      decoderUrl:
          '$_hfBase/sherpa-onnx-whisper-medium/resolve/main/medium-decoder.int8.onnx',
      tokensUrl:
          '$_hfBase/sherpa-onnx-whisper-medium/resolve/main/medium-tokens.txt',
      encoderFilename: 'medium-encoder.int8.onnx',
      decoderFilename: 'medium-decoder.int8.onnx',
      tokensFilename: 'medium-tokens.txt',
    ),
    SherpaModel(
      id: 'sense-voice',
      name: 'SenseVoice Small',
      description: 'Chinese/English/Japanese/Korean/Cantonese. Very fast.',
      sizeBytes: 230000000,
      encoderUrl:
          '$_hfBase/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx',
      decoderUrl: '', // SenseVoice uses single model file
      tokensUrl:
          '$_hfBase/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt',
      encoderFilename: 'model.int8.onnx',
      decoderFilename: '',
      tokensFilename: 'tokens.txt',
    ),
  ];
}
