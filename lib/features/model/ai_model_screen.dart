import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/model_manager.dart';
import '../../core/theme/colors.dart';
import '../../shared/widgets/glass_app_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/section_indicator.dart';

/// AI 模型管理页（多模型选择）
class AiModelScreen extends ConsumerStatefulWidget {
  const AiModelScreen({super.key});

  @override
  ConsumerState<AiModelScreen> createState() => _AiModelScreenState();
}

class _AiModelScreenState extends ConsumerState<AiModelScreen> {
  ModelStatus _status = ModelStatus.notDownloaded;
  double _progress = 0.0;
  double _speed = 0.0;
  String? _error;
  String? _downloadingId;
  ModelInfo? _currentModel;
  final Map<String, bool> _downloaded = {};

  StreamSubscription<ModelStatus>? _statusSub;
  StreamSubscription<double>? _progressSub;
  StreamSubscription<double>? _speedSub;
  StreamSubscription<void>? _modelChangedSub;

  @override
  void initState() {
    super.initState();
    final m = ModelManager.instance;
    _status = m.status;
    _progress = m.progress;
    _speed = m.speedBytesPerSec;
    _error = m.error;
    _downloadingId = m.downloadingId;

    _statusSub = m.statusStream.listen((s) {
      if (mounted) {
        setState(() {
          _status = s;
          _error = m.error;
          _downloadingId = m.downloadingId;
        });
        if (s == ModelStatus.ready) _refreshDownloaded();
      }
    });
    _progressSub = m.progressStream.listen((p) {
      if (mounted && (p - _progress).abs() >= 0.002) {
        setState(() => _progress = p);
      }
    });
    _speedSub = m.speedStream.listen((s) {
      if (mounted) setState(() => _speed = s);
    });
    _modelChangedSub = m.modelChangedStream.listen((_) {
      if (mounted) _refreshCurrent();
    });

    _initData();
  }

  Future<void> _initData() async {
    await _refreshCurrent();
    await _refreshDownloaded();
  }

  Future<void> _refreshCurrent() async {
    final model = await ModelManager.instance.currentModel;
    if (mounted) setState(() => _currentModel = model);
  }

  Future<void> _refreshDownloaded() async {
    for (final model in ModelManager.availableModels) {
      final ok = await ModelManager.instance.isModelDownloaded(model.id);
      _downloaded[model.id] = ok;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _progressSub?.cancel();
    _speedSub?.cancel();
    _modelChangedSub?.cancel();
    super.dispose();
  }

  Future<void> _download(ModelInfo model) async {
    await ModelManager.instance.download(model.id);
  }

  Future<void> _delete(ModelInfo model) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF241442),
        title: const Text('删除模型', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '删除 ${model.displayName}（${model.sizeLabel}）后需重新下载才能使用。',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ModelManager.instance.delete(model.id);
      await _refreshDownloaded();
    }
  }

  Future<void> _setActive(ModelInfo model) async {
    await ModelManager.instance.setCurrentModel(model.id);
    await _refreshCurrent();
  }

  String _fmtSpeed(double bps) {
    if (bps <= 0) return '';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: 'AI 模型'),
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: appBackgroundGradient)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionIndicator(
                    label: '端侧大模型',
                    colors: [AppColors.accent1, AppColors.accent2],
                  ),
                  const SizedBox(height: 16),
                  if (_currentModel != null) _buildCurrentHint(),
                  const SizedBox(height: 12),
                  ...ModelManager.availableModels.map(_buildModelCard),
                  const SizedBox(height: 16),
                  _buildDescription(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentHint() {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      backgroundOpacity: 0.08,
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, color: AppColors.accent2, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前使用：${_currentModel!.displayName}',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard(ModelInfo model) {
    final isCurrent = _currentModel?.id == model.id;
    final isDownloaded = _downloaded[model.id] ?? false;
    final isDownloading = _downloadingId == model.id && _status == ModelStatus.downloading;
    final isError = _downloadingId == model.id && _status == ModelStatus.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        borderRadius: 22,
        backgroundOpacity: isCurrent ? 0.14 : 0.10,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isCurrent ? Icons.star_rounded : Icons.auto_awesome_rounded,
                  color: isCurrent ? AppColors.accent2 : AppColors.accent1,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  model.displayName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                _chip(model.sizeLabel),
                if (model.recommended) ...[
                  const SizedBox(width: 6),
                  _chip('推荐', highlight: true),
                ],
                const Spacer(),
                if (isCurrent)
                  const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              model.description,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 6),
            Text(
              '建议手机 RAM ≥ ${model.recommendedRamGb}GB',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 14),
            _buildActionRow(model, isCurrent, isDownloaded, isDownloading, isError),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(ModelInfo model, bool isCurrent, bool isDownloaded, bool isDownloading, bool isError) {
    if (isDownloading) {
      final pct = (_progress * 100).toStringAsFixed(1);
      final speed = _fmtSpeed(_speed);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent1)),
              const SizedBox(width: 8),
              Text('下载中 $pct%', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (speed.isNotEmpty) Text(speed, style: const TextStyle(color: AppColors.accent4, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent1),
              minHeight: 6,
            ),
          ),
        ],
      );
    }

    if (isError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _download(model),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent1.withOpacity(0.85),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重新下载', style: TextStyle(fontSize: 14)),
            ),
          ),
        ],
      );
    }

    if (isDownloaded) {
      return Row(
        children: [
          Expanded(
            child: isCurrent
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success.withOpacity(0.4)),
                    ),
                    child: const Center(
                      child: Text('当前使用中', style: TextStyle(color: AppColors.success, fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  )
                : ElevatedButton(
                    onPressed: () => _setActive(model),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent2.withOpacity(0.85),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('设为当前', style: TextStyle(fontSize: 14)),
                  ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () => _delete(model),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger.withOpacity(0.4)),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Icon(Icons.delete_outline_rounded, size: 18),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _download(model),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent1.withOpacity(0.85),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.download_rounded, size: 20),
        label: Text('下载 ${model.sizeLabel}', style: const TextStyle(fontSize: 15)),
      ),
    );
  }

  Widget _buildDescription() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      backgroundOpacity: 0.06,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('关于端侧 AI', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
          SizedBox(height: 10),
          _Bullet('推理完全在手机本地完成，数据不上传。'),
          _Bullet('模型越大，对话和问答越智能，但占用空间和内存越多。'),
          _Bullet('下载后点「设为当前」即可在对话中使用，无需重启。'),
          _Bullet('未下载任何模型时使用基础离线助手。'),
          _Bullet('建议在 Wi-Fi 下下载，支持断点续传。'),
        ],
      ),
    );
  }

  Widget _chip(String text, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight ? AppColors.accent2.withOpacity(0.2) : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: highlight ? AppColors.accent2.withOpacity(0.5) : Colors.white.withOpacity(0.15)),
      ),
      child: Text(
        text,
        style: TextStyle(color: highlight ? AppColors.accent2 : AppColors.textSecondary, fontSize: 11),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 6, color: AppColors.accent1),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
