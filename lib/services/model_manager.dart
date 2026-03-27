import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/whisper_model.dart';

/// Model format version — bump when whisper.cpp is upgraded and old models
/// become incompatible. This forces re-download of all cached models.
const int _modelFormatVersion = 3;

/// Minimum expected file sizes (bytes) for new-format models (whisper.cpp v1.8+).
/// If a downloaded model is smaller than this, it's the old format and must be
/// re-downloaded.
const Map<String, int> _minModelSizes = {
  'tiny.en': 77000000,
  'tiny': 77000000,
  'base.en': 145000000,
  'base': 145000000,
  'small.en': 480000000,
  'small': 480000000,
  'medium.en': 1500000000,
  'medium': 1500000000,
  'large-v3-turbo': 1600000000,
};

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

    // Load persisted model selection
    final prefs = await SharedPreferences.getInstance();
    _selectedModelId = prefs.getString('selected_model');

    // Check model format version — if mismatch, purge old incompatible models
    final storedVersion = prefs.getInt('model_format_version') ?? 0;
    if (storedVersion < _modelFormatVersion) {
      debugPrint('[ModelManager] Model format upgraded ($storedVersion → $_modelFormatVersion), purging old models');
      await _purgeAllModels();
      await prefs.setInt('model_format_version', _modelFormatVersion);
      _selectedModelId = null;
      await prefs.remove('selected_model');
    }

    await _scanDownloadedModels();
  }

  Future<void> _purgeAllModels() async {
    if (_modelsDir == null) return;
    final dir = Directory(_modelsDir!);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.bin')) {
        debugPrint('[ModelManager] Deleting old model: ${entity.path}');
        await entity.delete();
      }
    }
  }

  Future<void> _scanDownloadedModels() async {
    _downloadedModels.clear();

    // Also check sandboxed container path (from previous installs) — macOS only
    final paths = <String>[_modelsDir!];
    if (Platform.isMacOS) {
      final containerPath = '${Platform.environment['HOME']}/Library/Containers/com.voiceink.voiceInk/Data/Library/Application Support/com.voiceink.voiceInk/models';
      paths.add(containerPath);
    }

    for (final dirPath in paths) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.bin')) {
          final name = p.basename(entity.path);
          if (name.startsWith('ggml-') && name.endsWith('.bin')) {
            final id = name.substring(5, name.length - 4);
            // Validate file size — reject old-format models
            final fileSize = await entity.length();
            final minSize = _minModelSizes[id];
            if (minSize != null && fileSize < minSize) {
              debugPrint('[ModelManager] Stale model $id detected ($fileSize < $minSize), deleting');
              await entity.delete();
              continue;
            }
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

    // Validate persisted selection still exists
    if (_selectedModelId != null && !_downloadedModels.contains(_selectedModelId)) {
      _selectedModelId = null;
    }
    // Auto-select first model if none selected
    if (_selectedModelId == null && _downloadedModels.isNotEmpty) {
      _selectedModelId = _downloadedModels.first;
      _persistSelection();
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
      // Validate downloaded file size against minimum expected
      final downloadedFile = File(filePath);
      final downloadedSize = await downloadedFile.length();
      final minSize = _minModelSizes[model.id];
      if (minSize != null && downloadedSize < minSize) {
        debugPrint('[ModelManager] Downloaded model ${model.id} too small: $downloadedSize < $minSize, deleting');
        await downloadedFile.delete();
        throw Exception('Downloaded model file is wrong format (${downloadedSize} bytes, expected >= $minSize). Please try again.');
      }
      debugPrint('[ModelManager] Model ${model.id} downloaded OK: $downloadedSize bytes');

      _downloadedModels.add(model.id);
      _downloadProgress.remove(model.id);
      if (_selectedModelId == null) {
        _selectedModelId = model.id;
        _persistSelection();
      }
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
      await prefs.setString('selected_model', _selectedModelId!);
    } else {
      await prefs.remove('selected_model');
    }
  }
}
