import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 模型下载与管理状态
enum ModelStatus {
  notDownloaded,
  downloading,
  ready,
  loading,
  running,
  error,
}

/// 可下载的端侧模型定义
class ModelInfo {
  final String id;
  final String displayName;
  final String sizeLabel;
  final int expectedFileSize;
  final String filename;
  final String primaryUrl;
  final String fallbackUrl;
  final String description;
  final int recommendedRamGb;
  final bool recommended;

  /// 是否支持 nobodywho 原生工具调用（创建日程/作业/课程）
  ///
  /// nobodywho 仅识别 qwen3 / qwen3.5 / qwen3.6 / gemma4 / lfm2 / ministral3 /
  /// functiongemma 的 tool-call 格式。传入 tools 但模型格式无法识别时，
  /// 创建 Chat 会直接抛异常，因此必须按模型能力区分。
  final bool supportsTools;

  const ModelInfo({
    required this.id,
    required this.displayName,
    required this.sizeLabel,
    required this.expectedFileSize,
    required this.filename,
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.description,
    required this.recommendedRamGb,
    this.recommended = false,
    this.supportsTools = false,
  });

  /// 有效模型的最小体积（小于该值视为损坏）
  int get minValidSize => (expectedFileSize * 0.85).toInt();
}

/// 端侧 LLM 模型管理器（多模型）
///
/// 支持多个 GGUF 模型的下载、切换与状态管理。
/// 当前选中模型持久化到 SharedPreferences。
class ModelManager {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  /// 可用模型清单（从小到大）
  static const List<ModelInfo> availableModels = [
    ModelInfo(
      id: 'qwen3-0.6b',
      displayName: 'Qwen3 0.6B',
      sizeLabel: '约 380MB',
      expectedFileSize: 379 * 1024 * 1024,
      filename: 'Qwen3-0.6B-Q4_K_M.gguf',
      primaryUrl:
          'https://hf-mirror.com/NobodyWho/Qwen_Qwen3-0.6B-GGUF/resolve/main/Qwen_Qwen3-0.6B-Q4_K_M.gguf',
      fallbackUrl:
          'https://huggingface.co/NobodyWho/Qwen_Qwen3-0.6B-GGUF/resolve/main/Qwen_Qwen3-0.6B-Q4_K_M.gguf',
      description: '轻量级千问，下载快、推理快，支持工具调用，适合入门体验',
      recommendedRamGb: 2,
      supportsTools: true,
    ),
    ModelInfo(
      id: 'qwen3-1.7b',
      displayName: 'Qwen3 1.7B',
      sizeLabel: '约 1.1GB',
      expectedFileSize: 1100 * 1024 * 1024,
      filename: 'Qwen3-1.7B-Q4_K_M.gguf',
      primaryUrl:
          'https://hf-mirror.com/NobodyWho/Qwen_Qwen3-1.7B-GGUF/resolve/main/Qwen_Qwen3-1.7B-Q4_K_M.gguf',
      fallbackUrl:
          'https://huggingface.co/NobodyWho/Qwen_Qwen3-1.7B-GGUF/resolve/main/Qwen_Qwen3-1.7B-Q4_K_M.gguf',
      description: '能力与速度平衡，支持工具调用，对话和问答质量明显更好',
      recommendedRamGb: 4,
      recommended: true,
      supportsTools: true,
    ),
    ModelInfo(
      id: 'qwen3-4b',
      displayName: 'Qwen3 4B',
      sizeLabel: '约 2.5GB',
      expectedFileSize: 2500 * 1024 * 1024,
      filename: 'Qwen3-4B-Q4_K_M.gguf',
      primaryUrl:
          'https://hf-mirror.com/NobodyWho/Qwen_Qwen3-4B-GGUF/resolve/main/Qwen_Qwen3-4B-Q4_K_M.gguf',
      fallbackUrl:
          'https://huggingface.co/NobodyWho/Qwen_Qwen3-4B-GGUF/resolve/main/Qwen_Qwen3-4B-Q4_K_M.gguf',
      description: '最强千问，支持工具调用，适合复杂问答与推理，需高端手机',
      recommendedRamGb: 8,
      supportsTools: true,
    ),
    ModelInfo(
      id: 'llama3.2-1b',
      displayName: 'Llama 3.2 1B',
      sizeLabel: '约 750MB',
      expectedFileSize: 750 * 1024 * 1024,
      filename: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      primaryUrl:
          'https://hf-mirror.com/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      fallbackUrl:
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      description: 'Meta 轻量模型，推理快，仅纯聊天（不支持工具调用）',
      recommendedRamGb: 2,
    ),
    ModelInfo(
      id: 'llama3.2-3b',
      displayName: 'Llama 3.2 3B',
      sizeLabel: '约 2.0GB',
      expectedFileSize: 2000 * 1024 * 1024,
      filename: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      primaryUrl:
          'https://hf-mirror.com/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      fallbackUrl:
          'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      description: 'Meta 中等模型，对话质量好，仅纯聊天（不支持工具调用）',
      recommendedRamGb: 4,
    ),
    ModelInfo(
      id: 'gemma2-2b',
      displayName: 'Gemma 2 2B',
      sizeLabel: '约 1.6GB',
      expectedFileSize: 1600 * 1024 * 1024,
      filename: 'gemma-2-2b-it-Q4_K_M.gguf',
      primaryUrl:
          'https://hf-mirror.com/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      fallbackUrl:
          'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      description: 'Google 模型，擅长问答与摘要，仅纯聊天（不支持工具调用）',
      recommendedRamGb: 4,
    ),
    ModelInfo(
      id: 'phi3.5-mini',
      displayName: 'Phi-3.5 mini',
      sizeLabel: '约 2.2GB',
      expectedFileSize: 2200 * 1024 * 1024,
      filename: 'Phi-3.5-mini-instruct-Q4_K_M.gguf',
      primaryUrl:
          'https://hf-mirror.com/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
      fallbackUrl:
          'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
      description: '微软模型，逻辑推理强，仅纯聊天（不支持工具调用）',
      recommendedRamGb: 4,
    ),
  ];

  static const String _currentModelKey = 'current_model_id';

  ModelInfo? _currentModel;
  String? _downloadingId;

  ModelStatus _status = ModelStatus.notDownloaded;
  double _progress = 0.0;
  double _speedBytesPerSec = 0.0;
  String? _error;

  final StreamController<ModelStatus> _statusCtrl =
      StreamController<ModelStatus>.broadcast();
  final StreamController<double> _progressCtrl =
      StreamController<double>.broadcast();
  final StreamController<double> _speedCtrl =
      StreamController<double>.broadcast();
  final StreamController<void> _modelChangedCtrl =
      StreamController<void>.broadcast();

  ModelStatus get status => _status;
  double get progress => _progress;
  double get speedBytesPerSec => _speedBytesPerSec;
  String? get error => _error;
  bool get isDownloading => _status == ModelStatus.downloading;
  String? get downloadingId => _downloadingId;

  Stream<ModelStatus> get statusStream => _statusCtrl.stream;
  Stream<double> get progressStream => _progressCtrl.stream;
  Stream<double> get speedStream => _speedCtrl.stream;
  Stream<void> get modelChangedStream => _modelChangedCtrl.stream;

  ModelInfo get defaultModel => availableModels[1];

  /// 当前选中的模型（异步，首次从 SharedPreferences 读取）
  Future<ModelInfo> get currentModel async {
    if (_currentModel != null) return _currentModel!;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_currentModelKey);
    if (id != null) {
      final m = availableModels.firstWhere(
        (m) => m.id == id,
        orElse: () => defaultModel,
      );
      _currentModel = m;
      return m;
    }
    _currentModel = defaultModel;
    return defaultModel;
  }

  /// 设置当前使用的模型
  Future<void> setCurrentModel(String id) async {
    final model = availableModels.firstWhere(
      (m) => m.id == id,
      orElse: () => defaultModel,
    );
    _currentModel = model;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentModelKey, id);
    _modelChangedCtrl.add(null);
  }

  /// 获取指定模型的本地路径（默认当前模型）
  Future<String> modelPath([String? id]) async {
    final model = id != null
        ? availableModels.firstWhere((m) => m.id == id)
        : await currentModel;
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/${model.filename}';
  }

  /// 检查指定模型是否已下载且完整（默认当前模型）
  Future<bool> isModelDownloaded([String? id]) async {
    final model = id != null
        ? availableModels.firstWhere((m) => m.id == id)
        : await currentModel;
    final path = await this.modelPath(model.id);
    final file = File(path);
    if (!await file.exists()) return false;
    final len = await file.length();
    return len >= model.minValidSize;
  }

  /// 检查任意模型是否已下载
  Future<bool> hasAnyDownloaded() async {
    for (final m in availableModels) {
      if (await isModelDownloaded(m.id)) return true;
    }
    return false;
  }

  /// 刷新状态（根据本地文件判断当前模型）
  Future<void> refresh() async {
    if (_status == ModelStatus.downloading ||
        _status == ModelStatus.loading ||
        _status == ModelStatus.running) {
      return;
    }
    if (await isModelDownloaded()) {
      _setStatus(ModelStatus.ready);
    } else {
      _setStatus(ModelStatus.notDownloaded);
    }
  }

  /// 开始下载指定模型（默认当前模型），支持断点续传 + 镜像回退
  Future<void> download([String? id]) async {
    final model = id != null
        ? availableModels.firstWhere((m) => m.id == id)
        : await currentModel;
    if (_status == ModelStatus.downloading) return;
    _downloadingId = model.id;
    _setStatus(ModelStatus.downloading);
    _error = null;
    _progress = 0.0;
    _speedBytesPerSec = 0.0;
    _progressCtrl.add(0.0);
    _speedCtrl.add(0.0);

    final path = await modelPath(model.id);
    final partFile = File('$path.part');

    Object? lastError;
    for (final url in [model.primaryUrl, model.fallbackUrl]) {
      try {
        await _downloadFrom(url, partFile, model);
        final finalFile = File(path);
        if (await finalFile.exists()) await finalFile.delete();
        await partFile.rename(path);

        final len = await finalFile.length();
        if (len < model.minValidSize) {
          throw Exception('下载的文件不完整（${len ~/ (1024 * 1024)} MB）');
        }
        _progress = 1.0;
        _progressCtrl.add(1.0);
        _downloadingId = null;
        await setCurrentModel(model.id);
        _setStatus(ModelStatus.ready);
        return;
      } catch (e) {
        lastError = e;
      }
    }

    _downloadingId = null;
    _error = lastError?.toString() ?? '下载失败';
    _setStatus(ModelStatus.error);
  }

  Future<void> _downloadFrom(String url, File partFile, ModelInfo model) async {
    int existing = await partFile.exists() ? await partFile.length() : 0;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(url));
      if (existing > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }
      final response = await request.close();

      final serverSupportsResume = response.statusCode == 206;
      if (existing > 0 && !serverSupportsResume) {
        existing = 0;
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('下载失败，HTTP ${response.statusCode}',
            uri: Uri.parse(url));
      }

      final remaining = response.contentLength;
      final total = remaining > 0
          ? remaining + existing
          : (existing > 0 ? model.expectedFileSize : model.expectedFileSize);

      final sink = partFile.openWrite(
        mode: existing > 0 ? FileMode.append : FileMode.write,
      );
      int downloaded = existing;
      final stopwatch = Stopwatch()..start();
      int lastEmitMs = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        downloaded += chunk.length;
        _progress = (downloaded / total).clamp(0.0, 1.0);
        _progressCtrl.add(_progress);

        final elapsedMs = stopwatch.elapsedMilliseconds;
        if (elapsedMs - lastEmitMs >= 500) {
          lastEmitMs = elapsedMs;
          if (elapsedMs > 0) {
            _speedBytesPerSec = downloaded / (elapsedMs / 1000.0);
            _speedCtrl.add(_speedBytesPerSec);
          }
        }
      }

      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
  }

  /// 删除指定模型（默认当前模型）
  Future<void> delete([String? id]) async {
    final model = id != null
        ? availableModels.firstWhere((m) => m.id == id)
        : await currentModel;
    final path = await modelPath(model.id);
    for (final p in ['$path', '$path.part']) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    _progress = 0.0;
    _speedBytesPerSec = 0.0;
    _error = null;
    _setStatus(ModelStatus.notDownloaded);
  }

  void markLoading() => _setStatus(ModelStatus.loading);
  void markRunning() => _setStatus(ModelStatus.running);
  void markError(String message) {
    _error = message;
    _setStatus(ModelStatus.error);
  }

  void _setStatus(ModelStatus s) {
    _status = s;
    _statusCtrl.add(s);
  }

  void dispose() {
    _statusCtrl.close();
    _progressCtrl.close();
    _speedCtrl.close();
    _modelChangedCtrl.close();
  }
}
