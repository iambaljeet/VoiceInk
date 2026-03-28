import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sherpa_model.dart';

/// Manages downloading, storing, and selecting sherpa-onnx models.
///
/// Each model consists of multiple files (encoder, decoder, tokens) stored
/// in a model-specific subdirectory under the app's models directory.
class SherpaModelManager extends ChangeNotifier {
  final Dio _dio = Dio();
  String? _modelsDir;
  String? _selectedModelId;
  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadedModels = {};
  CancelToken? _cancelToken;

  String? get selectedModelId => _selectedModelId;
  Map<String, double> get downloadProgress =>
      Map.unmodifiable(_downloadProgress);
  Set<String> get downloadedModels => Set.unmodifiable(_downloadedModels);

  bool isDownloaded(String modelId) => _downloadedModels.contains(modelId);
  bool isDownloading(String modelId) => _downloadProgress.containsKey(modelId);
  double? getProgress(String modelId) => _downloadProgress[modelId];

  /// Get the directory containing model files for a given model ID.
  String? getModelDir(String modelId) {
    if (_modelsDir == null || !_downloadedModels.contains(modelId)) return null;
    return p.join(_modelsDir!, modelId);
  }

  /// Get paths to encoder, decoder, and tokens files for the selected model.
  SherpaModelPaths? get selectedModelPaths {
    if (_selectedModelId == null) return null;
    return getModelPaths(_selectedModelId!);
  }

  SherpaModelPaths? getModelPaths(String modelId) {
    final dir = getModelDir(modelId);
    if (dir == null) return null;
    final model = SherpaModel.available.firstWhere(
      (m) => m.id == modelId,
      orElse: () => SherpaModel.available.first,
    );
    return SherpaModelPaths(
      encoder: p.join(dir, model.encoderFilename),
      decoder: model.decoderFilename.isNotEmpty
          ? p.join(dir, model.decoderFilename)
          : '',
      tokens: p.join(dir, model.tokensFilename),
      modelType: modelId.startsWith('sense-voice') ? 'sense_voice' : 'whisper',
    );
  }

  Future<void> init() async {
    final appDir = await getApplicationSupportDirectory();
    _modelsDir = p.join(appDir.path, 'sherpa_models');
    await Directory(_modelsDir!).create(recursive: true);

    final prefs = await SharedPreferences.getInstance();
    _selectedModelId = prefs.getString('sherpa_selected_model');

    await _scanDownloadedModels();
  }

  Future<void> _scanDownloadedModels() async {
    _downloadedModels.clear();
    if (_modelsDir == null) return;

    final dir = Directory(_modelsDir!);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final modelId = p.basename(entity.path);
        // Check model has required files
        final model = SherpaModel.available.where((m) => m.id == modelId);
        if (model.isNotEmpty) {
          final m = model.first;
          final hasEncoder =
              File(p.join(entity.path, m.encoderFilename)).existsSync();
          final hasTokens =
              File(p.join(entity.path, m.tokensFilename)).existsSync();
          final hasDecoder = m.decoderFilename.isEmpty ||
              File(p.join(entity.path, m.decoderFilename)).existsSync();
          if (hasEncoder && hasTokens && hasDecoder) {
            _downloadedModels.add(modelId);
          }
        }
      }
    }

    if (_selectedModelId != null &&
        !_downloadedModels.contains(_selectedModelId)) {
      _selectedModelId = null;
    }
    if (_selectedModelId == null && _downloadedModels.isNotEmpty) {
      _selectedModelId = _downloadedModels.first;
      _persistSelection();
    }
    notifyListeners();
  }

  Future<void> downloadModel(SherpaModel model) async {
    if (_modelsDir == null) return;
    if (_downloadedModels.contains(model.id)) return;

    final modelDir = p.join(_modelsDir!, model.id);
    await Directory(modelDir).create(recursive: true);

    _downloadProgress[model.id] = 0.0;
    _cancelToken = CancelToken();
    notifyListeners();

    try {
      // Download files: encoder, tokens, and optionally decoder
      final files = <MapEntry<String, String>>[];
      files.add(MapEntry(model.encoderUrl, model.encoderFilename));
      files.add(MapEntry(model.tokensUrl, model.tokensFilename));
      if (model.decoderUrl.isNotEmpty) {
        files.add(MapEntry(model.decoderUrl, model.decoderFilename));
      }

      for (int i = 0; i < files.length; i++) {
        final entry = files[i];
        final filePath = p.join(modelDir, entry.value);
        await _dio.download(
          entry.key,
          filePath,
          cancelToken: _cancelToken,
          onReceiveProgress: (received, total) {
            // Approximate progress across all files
            final fileProgress = (i + (total > 0 ? received / total : 0));
            _downloadProgress[model.id] = fileProgress / files.length;
            notifyListeners();
          },
        );
      }

      _downloadedModels.add(model.id);
      _downloadProgress.remove(model.id);
      if (_selectedModelId == null) {
        _selectedModelId = model.id;
        _persistSelection();
      }
    } catch (e) {
      _downloadProgress.remove(model.id);
      // Clean up partial download
      final dir = Directory(modelDir);
      if (await dir.exists()) await dir.delete(recursive: true);
      if (e is! DioException || e.type != DioExceptionType.cancel) {
        rethrow;
      }
    } finally {
      _cancelToken = null;
      notifyListeners();
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel();
  }

  Future<void> deleteModel(String modelId) async {
    if (_modelsDir == null) return;
    final dir = Directory(p.join(_modelsDir!, modelId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _downloadedModels.remove(modelId);
    if (_selectedModelId == modelId) {
      _selectedModelId =
          _downloadedModels.isNotEmpty ? _downloadedModels.first : null;
      _persistSelection();
    }
    notifyListeners();
  }

  void selectModel(String modelId) {
    if (_downloadedModels.contains(modelId)) {
      _selectedModelId = modelId;
      _persistSelection();
      notifyListeners();
    }
  }

  Future<void> _persistSelection() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedModelId != null) {
      await prefs.setString('sherpa_selected_model', _selectedModelId!);
    } else {
      await prefs.remove('sherpa_selected_model');
    }
  }
}

/// Paths to the model files for a sherpa-onnx model.
class SherpaModelPaths {
  final String encoder;
  final String decoder;
  final String tokens;
  final String modelType;

  const SherpaModelPaths({
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.modelType,
  });
}
