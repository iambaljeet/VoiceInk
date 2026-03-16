import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../models/whisper_model.dart';

/// Manages downloading, storing, and selecting whisper models
class ModelManager extends ChangeNotifier {
  final Dio _dio = Dio();
  String? _modelsDir;
  String? _selectedModelId;
  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadedModels = {};
  CancelToken? _cancelToken;

  String? get selectedModelId => _selectedModelId;
  Map<String, double> get downloadProgress => Map.unmodifiable(_downloadProgress);
  Set<String> get downloadedModels => Set.unmodifiable(_downloadedModels);

  bool isDownloaded(String modelId) => _downloadedModels.contains(modelId);
  bool isDownloading(String modelId) => _downloadProgress.containsKey(modelId);
  double? getProgress(String modelId) => _downloadProgress[modelId];

  String? getModelPath(String modelId) {
    if (_modelsDir == null || !_downloadedModels.contains(modelId)) return null;
    return '$_modelsDir/ggml-$modelId.bin';
  }

  String? get selectedModelPath {
    if (_selectedModelId == null) return null;
    return getModelPath(_selectedModelId!);
  }

  Future<void> init() async {
    final appDir = await getApplicationSupportDirectory();
    _modelsDir = '${appDir.path}/models';
    await Directory(_modelsDir!).create(recursive: true);
    await _scanDownloadedModels();
  }

  Future<void> _scanDownloadedModels() async {
    _downloadedModels.clear();

    // Also check sandboxed container path (from previous installs)
    final containerPath = '${Platform.environment['HOME']}/Library/Containers/com.voiceink.voiceInk/Data/Library/Application Support/com.voiceink.voiceInk/models';
    for (final dirPath in [_modelsDir!, containerPath]) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.bin')) {
          final name = entity.path.split('/').last;
          if (name.startsWith('ggml-') && name.endsWith('.bin')) {
            final id = name.substring(5, name.length - 4);
            if (!_downloadedModels.contains(id)) {
              // Copy from container to non-sandboxed location if needed
              if (dirPath != _modelsDir) {
                final destPath = '$_modelsDir/$name';
                if (!await File(destPath).exists()) {
                  await entity.copy(destPath);
                }
              }
              _downloadedModels.add(id);
            }
          }
        }
      }
    }

    if (_selectedModelId == null && _downloadedModels.isNotEmpty) {
      _selectedModelId = _downloadedModels.first;
    }
    notifyListeners();
  }

  Future<void> downloadModel(WhisperModel model) async {
    if (_modelsDir == null) return;
    if (_downloadedModels.contains(model.id)) return;

    final filePath = '$_modelsDir/ggml-${model.id}.bin';
    _downloadProgress[model.id] = 0.0;
    _cancelToken = CancelToken();
    notifyListeners();

    try {
      await _dio.download(
        model.downloadUrl,
        filePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _downloadProgress[model.id] = received / total;
            notifyListeners();
          }
        },
      );
      _downloadedModels.add(model.id);
      _downloadProgress.remove(model.id);
      _selectedModelId ??= model.id;
    } catch (e) {
      _downloadProgress.remove(model.id);
      // Clean up partial download
      final file = File(filePath);
      if (await file.exists()) await file.delete();
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
    final file = File('$_modelsDir/ggml-$modelId.bin');
    if (await file.exists()) {
      await file.delete();
    }
    _downloadedModels.remove(modelId);
    if (_selectedModelId == modelId) {
      _selectedModelId = _downloadedModels.isNotEmpty
          ? _downloadedModels.first
          : null;
    }
    notifyListeners();
  }

  void selectModel(String modelId) {
    if (_downloadedModels.contains(modelId)) {
      _selectedModelId = modelId;
      notifyListeners();
    }
  }
}
