import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Progress info for model downloads
class DownloadProgress {
  final int bytesReceived;
  final int totalBytes;
  final double progress;
  final String? currentFile;
  final String? modelName;
  final int completedFiles;
  final int totalFiles;
  final double currentFileProgress;

  const DownloadProgress({
    required this.bytesReceived,
    required this.totalBytes,
    required this.progress,
    this.currentFile,
    this.modelName,
    this.completedFiles = 0,
    this.totalFiles = 0,
    this.currentFileProgress = 0,
  });

  factory DownloadProgress.zero() => const DownloadProgress(
        bytesReceived: 0,
        totalBytes: 0,
        progress: 0,
      );
}

enum ModelType { asr, tts, llm, embedding }

class ModelInfo {
  final ModelType type;
  final String name;
  final String repoId;
  final List<String> files;
  final String subDir;

  const ModelInfo({
    required this.type,
    required this.name,
    required this.repoId,
    required this.files,
    required this.subDir,
  });
}

class _PlannedDownload {
  final ModelInfo model;
  final String file;
  final File targetFile;
  final String url;
  final int? expectedBytes;

  const _PlannedDownload({
    required this.model,
    required this.file,
    required this.targetFile,
    required this.url,
    required this.expectedBytes,
  });
}

class ModelManager {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  static const _onboardingKey = 'onboarding_complete';
  static const _legacyAsrTokenFile = 'base-tokens.txt';
  static const _currentAsrTokenFile = 'tiny.en-tokens.txt';
  static const _llmRuntimeConfigFile = 'llm_config.json';
  static const _llmVisionKeys = <String>{
    'image_mean',
    'image_norm',
    'image_size',
    'vision_start',
    'vision_end',
    'image_pad',
    'video_pad',
    'num_grid_per_side',
    'has_deepstack',
  };

  Directory? _modelsDir;
  SharedPreferences? _prefs;
  Future<void>? _initializeFuture;
  Future<Map<ModelType, bool>>? _modelStatusFuture;
  final Map<ModelType, bool> _modelStatusCache = {};

  final _progressController = StreamController<DownloadProgress>.broadcast();
  Stream<DownloadProgress> get downloadProgress => _progressController.stream;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 10),
    headers: const {
      'User-Agent': 'NoorAI/1.0',
      'Accept': '*/*',
    },
  ));

  // Model definitions
  static const models = <ModelInfo>[
    ModelInfo(
      type: ModelType.asr,
      name: 'Whisper Tiny EN ASR',
      repoId: 'developerabu/whisper-tiny-en-mnn',
      files: [
        'encode.mnn',
        'decode.mnn',
        'tiny.en-tokens.txt',
      ],
      subDir: 'whisper',
    ),
    ModelInfo(
      type: ModelType.tts,
      name: 'Supertonic TTS',
      repoId: 'yunfengwang/supertonic-tts-mnn',
      files: [
        'mnn_models/tts.json',
        'mnn_models/unicode_indexer.json',
        'mnn_models/int8/duration_predictor.mnn',
        'mnn_models/int8/text_encoder.mnn',
        'mnn_models/int8/vector_estimator.mnn',
        'mnn_models/int8/vocoder.mnn',
        'voice_styles/F1.json',
        'voice_styles/F2.json',
        'voice_styles/M1.json',
        'voice_styles/M2.json',
      ],
      subDir: 'tts',
    ),
    ModelInfo(
      type: ModelType.llm,
      name: 'Qwen 3.5 0.8B',
      repoId: 'taobao-mnn/Qwen3.5-0.8B-MNN',
      files: [
        'config.json',
        'llm.mnn',
        'llm.mnn.weight',
        'tokenizer.txt',
        'llm_config.json',
      ],
      subDir: 'llm',
    ),
    ModelInfo(
      type: ModelType.embedding,
      name: 'BGE Small Embeddings',
      repoId: 'developerabu/bge-small-en-v1.5-mnn',
      files: [
        'model.mnn',
        'tokenizer.json',
      ],
      subDir: 'embedding',
    ),
  ];

  Future<void> initialize() {
    _initializeFuture ??= _initializeInternal();
    return _initializeFuture!;
  }

  Future<void> _initializeInternal() async {
    _prefs = await SharedPreferences.getInstance();
    final appDir = await getApplicationDocumentsDirectory();
    _modelsDir = Directory('${appDir.path}/models');
    if (!await _modelsDir!.exists()) {
      await _modelsDir!.create(recursive: true);
    }
  }

  bool get isOnboardingComplete => _prefs?.getBool(_onboardingKey) ?? false;

  Future<void> completeOnboarding() async {
    await _prefs?.setBool(_onboardingKey, true);
  }

  String get modelsPath => _modelsDir?.path ?? '';

  String modelPath(ModelType type) {
    final info = models.firstWhere((m) => m.type == type);
    final basePath = _modelsDir?.path;
    if (basePath == null) return '';
    return '$basePath/${info.subDir}';
  }

  String llmRuntimeConfigPath() {
    final llmDir = modelPath(ModelType.llm);
    if (llmDir.isEmpty) {
      return '';
    }

    final runtimeConfigPath = '$llmDir/$_llmRuntimeConfigFile';
    if (File(runtimeConfigPath).existsSync()) {
      return runtimeConfigPath;
    }

    final defaultConfigPath = '$llmDir/config.json';
    if (File(defaultConfigPath).existsSync()) {
      return defaultConfigPath;
    }

    return runtimeConfigPath;
  }

  Future<void> ensureRuntimeReady(ModelType type) async {
    await initialize();
    final info = models.firstWhere((m) => m.type == type);
    final dir = Directory('${_modelsDir!.path}/${info.subDir}');
    if (!await dir.exists()) {
      return;
    }
    await _prepareModelDirectory(info, dir);
  }

  /// Check if a specific model type has all required files
  Future<bool> isModelDownloaded(
    ModelType type, {
    bool forceRefresh = false,
  }) async {
    final states = await getDownloadedModelStates(forceRefresh: forceRefresh);
    return states[type] ?? false;
  }

  /// Check if all models are downloaded
  Future<bool> areAllModelsDownloaded({bool forceRefresh = false}) async {
    final states = await getDownloadedModelStates(forceRefresh: forceRefresh);
    return states.values.every((isDownloaded) => isDownloaded);
  }

  Future<bool> areRagModelsDownloaded({bool forceRefresh = false}) async {
    final states = await getDownloadedModelStates(forceRefresh: forceRefresh);
    return (states[ModelType.llm] ?? false) &&
        (states[ModelType.embedding] ?? false);
  }

  Future<Map<ModelType, bool>> getDownloadedModelStates({
    bool forceRefresh = false,
  }) async {
    await initialize();

    if (!forceRefresh && _modelStatusCache.length == models.length) {
      return Map<ModelType, bool>.unmodifiable(_modelStatusCache);
    }

    if (!forceRefresh && _modelStatusFuture != null) {
      return Map<ModelType, bool>.unmodifiable(await _modelStatusFuture!);
    }

    final future = _scanDownloadedModelStates();
    _modelStatusFuture = future;

    try {
      final states = await future;
      _modelStatusCache
        ..clear()
        ..addAll(states);
      return Map<ModelType, bool>.unmodifiable(states);
    } finally {
      if (identical(_modelStatusFuture, future)) {
        _modelStatusFuture = null;
      }
    }
  }

  Future<Map<ModelType, bool>> _scanDownloadedModelStates() async {
    final states = <ModelType, bool>{};

    for (final model in models) {
      final dir = Directory('${_modelsDir!.path}/${model.subDir}');
      var isDownloaded = await dir.exists();

      if (isDownloaded) {
        for (final file in model.files) {
          final targetFile = File('${dir.path}/$file');
          if (!await targetFile.exists() || await targetFile.length() == 0) {
            isDownloaded = false;
            break;
          }
        }
      }

      states[model.type] = isDownloaded;
    }

    return states;
  }

  /// Download a specific model from HuggingFace
  Future<void> downloadModel(ModelInfo model, {CancelToken? cancelToken}) async {
    _invalidateModelStatusCache();
    final downloads = await _buildPendingDownloads(model: model);
    await _runDownloads(downloads, cancelToken: cancelToken);
    _invalidateModelStatusCache();
  }

  /// Download all models
  Future<void> downloadAllModels({CancelToken? cancelToken}) async {
    _invalidateModelStatusCache();
    final downloads = await _buildPendingDownloads();
    await _runDownloads(downloads, cancelToken: cancelToken);
    _invalidateModelStatusCache();
  }

  void _invalidateModelStatusCache() {
    _modelStatusCache.clear();
    _modelStatusFuture = null;
  }

  Future<List<_PlannedDownload>> _buildPendingDownloads({ModelInfo? model}) async {
    await initialize();

    final downloads = <_PlannedDownload>[];
    final targetModels = model == null ? models : <ModelInfo>[model];

    for (final entry in targetModels) {
      final dir = Directory('${_modelsDir!.path}/${entry.subDir}');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      await _prepareModelDirectory(entry, dir);

      for (final file in entry.files) {
        final targetFile = File('${dir.path}/$file');
        final tempFile = File('${targetFile.path}.part');
        final parentDir = targetFile.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }

        final url = 'https://huggingface.co/${entry.repoId}/resolve/main/$file';
        final expectedBytes = await _fetchRemoteFileSize(url);

        if (await targetFile.exists() && await targetFile.length() > 0) {
          final existingBytes = await targetFile.length();
          if (expectedBytes != null && existingBytes == expectedBytes) {
            debugPrint('ModelManager: Skipping ${entry.name}/$file (complete)');
            continue;
          }

          if (!await tempFile.exists()) {
            await targetFile.rename(tempFile.path);
          } else {
            await _deleteIfExists(targetFile);
          }
        }

        if (await tempFile.exists() && expectedBytes != null) {
          final partialBytes = await tempFile.length();
          if (partialBytes == expectedBytes) {
            await tempFile.rename(targetFile.path);
            debugPrint('ModelManager: Recovered completed partial ${entry.name}/$file');
            continue;
          }

          if (partialBytes > expectedBytes) {
            await _deleteIfExists(tempFile);
          }
        }

        downloads.add(_PlannedDownload(
          model: entry,
          file: file,
          targetFile: targetFile,
          url: url,
          expectedBytes: expectedBytes,
        ));
      }
    }

    return downloads;
  }

  Future<void> _prepareModelDirectory(ModelInfo model, Directory dir) async {
    if (model.type == ModelType.llm) {
      await _sanitizeLlmRuntimeConfig(dir);
      return;
    }

    if (model.type != ModelType.asr) {
      return;
    }

    final expectedTokenFile = File('${dir.path}/$_currentAsrTokenFile');
    final legacyTokenFile = File('${dir.path}/$_legacyAsrTokenFile');
    final hasExpectedToken = await expectedTokenFile.exists() &&
        await expectedTokenFile.length() > 0;
    final hasLegacyToken = await legacyTokenFile.exists() &&
        await legacyTokenFile.length() > 0;

    if (hasLegacyToken && !hasExpectedToken) {
      await _deleteIfExists(File('${dir.path}/encode.mnn'));
      await _deleteIfExists(File('${dir.path}/decode.mnn'));
      await _deleteIfExists(expectedTokenFile);
      await _deleteIfExists(legacyTokenFile);
      debugPrint('ModelManager: Cleared legacy ASR bundle to migrate to whisper-tiny-en-mnn');
      return;
    }

    if (hasLegacyToken && hasExpectedToken) {
      await _deleteIfExists(legacyTokenFile);
      debugPrint('ModelManager: Removed legacy ASR token file after tiny model migration');
    }
  }

  Future<void> _sanitizeLlmRuntimeConfig(Directory dir) async {
    final configFile = File('${dir.path}/$_llmRuntimeConfigFile');
    if (!await configFile.exists() || await configFile.length() == 0) {
      return;
    }

    try {
      final raw = await configFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      var changed = false;
      if (decoded['is_visual'] != false) {
        decoded['is_visual'] = false;
        changed = true;
      }

      for (final key in _llmVisionKeys) {
        if (decoded.remove(key) != null) {
          changed = true;
        }
      }

      if (!changed) {
        return;
      }

      await configFile.writeAsString(const JsonEncoder.withIndent('  ').convert(decoded));
      debugPrint('ModelManager: Sanitized llm_config.json for text-only runtime');
    } catch (error) {
      debugPrint('ModelManager: Failed to sanitize llm_config.json: $error');
    }
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _runDownloads(
    List<_PlannedDownload> downloads, {
    CancelToken? cancelToken,
  }) async {
    if (downloads.isEmpty) {
      _progressController.add(const DownloadProgress(
        bytesReceived: 0,
        totalBytes: 0,
        progress: 1,
        completedFiles: 0,
        totalFiles: 0,
        currentFileProgress: 1,
      ));
      return;
    }

    final totalFiles = downloads.length;
    var completedFiles = 0;

    for (final download in downloads) {
      debugPrint('ModelManager: Downloading ${download.url}');

      _progressController.add(DownloadProgress(
        bytesReceived: 0,
        totalBytes: 0,
        progress: completedFiles / totalFiles,
        currentFile: download.file,
        modelName: download.model.name,
        completedFiles: completedFiles,
        totalFiles: totalFiles,
        currentFileProgress: 0,
      ));

      await _downloadPlannedFile(
        download,
        completedFiles: completedFiles,
        totalFiles: totalFiles,
        cancelToken: cancelToken,
      );

      if (!await download.targetFile.exists() || await download.targetFile.length() == 0) {
        throw Exception(
          'Downloaded file is empty: ${download.model.name}/${download.file}',
        );
      }

      completedFiles += 1;
      _progressController.add(DownloadProgress(
        bytesReceived: 0,
        totalBytes: 0,
        progress: completedFiles / totalFiles,
        currentFile: download.file,
        modelName: download.model.name,
        completedFiles: completedFiles,
        totalFiles: totalFiles,
        currentFileProgress: 1,
      ));
    }
  }

  Future<int?> _fetchRemoteFileSize(String url) async {
    try {
      final response = await _dio.head<void>(
        url,
        options: Options(
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
      );

      final headerValue = response.headers.value(Headers.contentLengthHeader) ??
          response.headers.value('x-linked-size');
      return int.tryParse(headerValue ?? '');
    } catch (error) {
      debugPrint('ModelManager: Failed to fetch remote size for $url: $error');
      return null;
    }
  }

  Future<void> _downloadPlannedFile(
    _PlannedDownload download, {
    required int completedFiles,
    required int totalFiles,
    CancelToken? cancelToken,
  }) async {
    final tempFile = File('${download.targetFile.path}.part');
    final existingBytes = await tempFile.exists() ? await tempFile.length() : 0;
    final expectedBytes = download.expectedBytes ?? 0;

    final response = await _dio.get<ResponseBody>(
      download.url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: existingBytes > 0 ? {'Range': 'bytes=$existingBytes-'} : null,
        validateStatus: (status) => status == 200 || status == 206,
      ),
    );

    final responseBody = response.data;
    if (responseBody == null) {
      throw Exception('Download response body missing for ${download.file}');
    }

    final sink = tempFile.openWrite(
      mode: existingBytes > 0 ? FileMode.append : FileMode.write,
    );

    var receivedThisSession = 0;
    try {
      await for (final chunk in responseBody.stream) {
        sink.add(chunk);
        receivedThisSession += chunk.length;

        final bytesReceived = existingBytes + receivedThisSession;
        final totalBytes = expectedBytes > 0 ? expectedBytes : bytesReceived;
        final currentFileProgress = totalBytes > 0 ? bytesReceived / totalBytes : 0.0;
        final overallProgress = (completedFiles + currentFileProgress) / totalFiles;

        _progressController.add(DownloadProgress(
          bytesReceived: bytesReceived,
          totalBytes: totalBytes,
          progress: overallProgress.clamp(0.0, 1.0),
          currentFile: download.file,
          modelName: download.model.name,
          completedFiles: completedFiles,
          totalFiles: totalFiles,
          currentFileProgress: currentFileProgress.clamp(0.0, 1.0),
        ));
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    final finalBytes = await tempFile.length();
    if (download.expectedBytes != null && finalBytes != download.expectedBytes) {
      throw Exception(
        'Downloaded file incomplete: ${download.model.name}/${download.file} '
        '($finalBytes/${download.expectedBytes} bytes)',
      );
    }

    if (await download.targetFile.exists()) {
      await download.targetFile.delete();
    }
    await tempFile.rename(download.targetFile.path);
  }

  /// Delete all models
  Future<void> deleteAllModels() async {
    await initialize();
    if (_modelsDir != null && await _modelsDir!.exists()) {
      await _modelsDir!.delete(recursive: true);
      await _modelsDir!.create(recursive: true);
    }
    await _prefs?.setBool(_onboardingKey, false);
  }

  /// Get total size of downloaded models
  Future<int> getTotalModelSize() async {
    await initialize();
    if (_modelsDir == null || !await _modelsDir!.exists()) return 0;
    int total = 0;
    await for (final entity in _modelsDir!.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  void dispose() {
    _progressController.close();
  }
}
