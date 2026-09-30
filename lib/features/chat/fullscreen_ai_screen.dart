import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/colors.dart';
import '../../core/providers.dart';
import '../../core/llm/model_manager.dart';
import '../../core/utils/app_log.dart';
import '../../shared/widgets/glass_app_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/section_indicator.dart';
import '../../shared/widgets/animated_indicators.dart';
import '../model/ai_model_screen.dart';
import 'chat_controller.dart';

/// 全屏 AI 对话页（千问模型 — 自由聊天 + 工具调用）
class FullScreenAiScreen extends ConsumerStatefulWidget {
  const FullScreenAiScreen({super.key});

  @override
  ConsumerState<FullScreenAiScreen> createState() => _FullScreenAiScreenState();
}

class _FullScreenAiScreenState extends ConsumerState<FullScreenAiScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiChatMessagesProvider.notifier).ensureSession();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _inputCtrl.clear();
    try {
      await ref.read(aiChatMessagesProvider.notifier).send(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _scrollToBottom();
  }

  void _openModelManager() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiModelScreen()),
    );
  }

  /// 查看运行日志（排查 AI 异常）
  void _openLogs() => _showLogsDialog(context);

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(aiChatMessagesProvider);
    if (messages.isNotEmpty) _scrollToBottom();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: _ModelSwitchButton(),
        title: 'AI 助手',
        actions: [
          GlassIconButton(
            icon: const Icon(Icons.receipt_long_rounded),
            onTap: _openLogs,
          ),
          GlassIconButton(
            icon: const Icon(Icons.memory_rounded),
            onTap: _openModelManager,
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: appBackgroundGradient)),
          SafeArea(
            child: Column(
              children: [
                _ModelLoadingHint(),
                Expanded(child: _buildMessages(messages)),
                _buildInput(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(List<UIMessage> messages) {
    if (messages.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PulsingDot(size: 16, color: AppColors.accent2),
              const SizedBox(height: 16),
              const Text(
                '千问 AI 助手',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '下载模型后即可自由对话\n能聊天、解数学题、管理日程作业',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              _QuickPrompts(),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: messages.length,
      itemBuilder: (ctx, i) {
        final m = messages[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _MessageBubble(message: m)
              .animate()
              .fadeIn(duration: 300.ms, delay: (i * 20).ms)
              .slideY(begin: 0.04, duration: 300.ms, curve: Curves.easeOutCubic),
        );
      },
    );
  }

  Widget _buildInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        borderRadius: 26,
        blurSigma: 18,
        backgroundOpacity: 0.14,
        child: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: 44,
                width: 44,
                child: IconButton(
                  onPressed: _sending ? null : () => _showActions(context),
                  icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.accent1),
                  iconSize: 24,
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    height: 1.4,
                  ),
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration.collapsed(
                    hintText: '和千问 AI 聊聊...',
                    hintStyle: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 44,
                height: 44,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.accent1, AppColors.accent2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: _sending
                    ? const Center(child: PulsingDot(size: 10, color: Colors.white))
                    : IconButton(
                        onPressed: _send,
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                        padding: EdgeInsets.zero,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassCard(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(20),
        borderRadius: 28,
        backgroundOpacity: 0.16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionIndicator(
              label: '快捷操作',
              colors: [AppColors.accent1, AppColors.accent3],
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.event_available_rounded, color: AppColors.accent2),
              title: const Text('添加日程'),
              subtitle: const Text('让 AI 帮你创建日程提醒'),
              onTap: () {
                Navigator.pop(ctx);
                _inputCtrl.text = '明天下午3点开会';
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.assignment_rounded, color: AppColors.accent3),
              title: const Text('添加作业'),
              subtitle: const Text('让 AI 帮你创建作业'),
              onTap: () {
                Navigator.pop(ctx);
                _inputCtrl.text = '后天交《高等数学》第3章习题';
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_week_rounded, color: AppColors.accent4),
              title: const Text('添加课程'),
              subtitle: const Text('让 AI 帮你添加课程'),
              onTap: () {
                Navigator.pop(ctx);
                _inputCtrl.text = '周一第3节有《英语》课，教室A201';
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.calculate_rounded, color: AppColors.accent1),
              title: const Text('解数学题'),
              subtitle: const Text('让 AI 帮你计算'),
              onTap: () {
                Navigator.pop(ctx);
                _inputCtrl.text = 'cos 30度等于多少？';
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 左上角模型切换按钮
class _ModelSwitchButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ModelSwitchButton> createState() => _ModelSwitchButtonState();
}

class _ModelSwitchButtonState extends ConsumerState<_ModelSwitchButton> {
  ModelInfo? _currentModel;
  final Map<String, bool> _downloaded = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final model = await ModelManager.instance.currentModel;
    if (mounted) setState(() => _currentModel = model);
    for (final m in ModelManager.availableModels) {
      _downloaded[m.id] = await ModelManager.instance.isModelDownloaded(m.id);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (id) async {
        await ModelManager.instance.setCurrentModel(id);
        final model = ModelManager.availableModels.firstWhere((m) => m.id == id);
        if (mounted) setState(() => _currentModel = model);
      },
      tooltip: '切换模型',
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.15), width: 1),
      ),
      color: const Color(0xFF241442),
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.accent2),
            const SizedBox(width: 6),
            Text(
              _currentModel?.displayName ?? '选择模型',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
      itemBuilder: (ctx) => ModelManager.availableModels.map((m) {
        final isDownloaded = _downloaded[m.id] ?? false;
        final isCurrent = _currentModel?.id == m.id;
        return PopupMenuItem<String>(
          value: m.id,
          enabled: isDownloaded,
          height: 40,
          child: Row(
            children: [
              Icon(
                isDownloaded ? Icons.check_circle_rounded : Icons.download_rounded,
                size: 16,
                color: isDownloaded ? AppColors.accent1 : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                isDownloaded ? m.displayName : '${m.displayName}（未下载）',
                style: TextStyle(
                  fontSize: 13,
                  color: isDownloaded ? AppColors.textPrimary : AppColors.textMuted,
                ),
              ),
              if (isCurrent) ...[
                const Spacer(),
                const Icon(Icons.star_rounded, size: 14, color: AppColors.accent2),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// 模型加载提示
class _ModelLoadingHint extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ModelLoadingHint> createState() => _ModelLoadingHintState();
}

class _ModelLoadingHintState extends ConsumerState<_ModelLoadingHint> {
  ModelStatus _status = ModelManager.instance.status;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _status = ModelManager.instance.status;
    ModelManager.instance.statusStream.listen((s) {
      if (mounted) {
        setState(() {
          _status = s;
          if (s != ModelStatus.error) _expanded = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_status == ModelStatus.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent2),
            ),
            SizedBox(width: 10),
            Text(
              '千问模型加载中，请稍候…',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (_status == ModelStatus.notDownloaded) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.download_rounded, size: 16, color: AppColors.accent4),
            const SizedBox(width: 8),
            const Text(
              '尚未下载模型，点击右上角下载',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (_status == ModelStatus.error) {
      final err = ModelManager.instance.error ?? '模型加载失败';
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      err,
                      style: const TextStyle(color: AppColors.danger, fontSize: 12),
                      maxLines: _expanded ? null : 2,
                      overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: AppColors.danger,
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: err));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('错误信息已复制')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('复制错误', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton.icon(
                    onPressed: () => _showLogsDialog(context),
                    icon: const Icon(Icons.receipt_long_rounded, size: 14),
                    label: const Text('查看日志', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 日志弹窗（供错误提示与右上角按钮复用）
void _showLogsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => Dialog(
        backgroundColor: const Color(0xFF241442),
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('运行日志', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        AppLog.instance.clear();
                        setLocal(() {});
                      },
                      child: const Text('清空', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () {
                        final all = AppLog.instance.lines.join('\n');
                        Clipboard.setData(ClipboardData(text: all));
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('日志已复制')));
                      },
                      child: const Text('复制全部', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('关闭', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 380,
                  width: double.maxFinite,
                  child: StreamBuilder<List<String>>(
                    stream: AppLog.instance.stream,
                    initialData: AppLog.instance.lines,
                    builder: (ctx, snap) {
                      final lines = snap.data ?? const <String>[];
                      if (lines.isEmpty) {
                        return const Center(
                          child: Text('暂无日志', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        );
                      }
                      return ListView(
                        reverse: true,
                        children: [
                          for (final l in lines.reversed)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: SelectableText(
                                l,
                                style: TextStyle(
                                  color: l.contains('[ERROR]')
                                      ? AppColors.danger
                                      : l.contains('[WARN]')
                                          ? AppColors.warning
                                          : AppColors.textSecondary,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _QuickPrompts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final prompts = [
      ('你好，介绍一下你自己', Icons.waving_hand_rounded, AppColors.accent2),
      ('cos 30度等于多少？', Icons.calculate_rounded, AppColors.accent1),
      ('明天下午3点开会', Icons.event_available_rounded, AppColors.accent3),
      ('怎么学英语更高效？', Icons.school_rounded, AppColors.accent4),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: prompts
          .map((p) => Chip(
                label: Text(p.$1, style: const TextStyle(fontSize: 13)),
                avatar: Icon(p.$2, size: 18, color: p.$3),
                backgroundColor: Colors.white.withOpacity(0.08),
                side: BorderSide(color: Colors.white.withOpacity(0.12)),
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              ))
          .toList(),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final UIMessage message;
  const _MessageBubble({required this.message});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _toolExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == 'user';
    final isTool = widget.message.role == 'tool';

    if (isTool) {
      final isError = widget.message.content.contains('【错误详情】') ||
          widget.message.content.contains('[ERROR]') ||
          widget.message.content.contains('失败');
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isError
                ? AppColors.danger.withOpacity(0.10)
                : AppColors.accent4.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isError
                  ? AppColors.danger.withOpacity(0.35)
                  : AppColors.accent4.withOpacity(0.25),
              width: 1,
            ),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _toolExpanded = !_toolExpanded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isError
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_rounded,
                      size: 14,
                      color: isError ? AppColors.danger : AppColors.accent4,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isError ? '模型调用失败（点按展开详情）' : widget.message.content,
                        style: TextStyle(
                          color: isError
                              ? AppColors.danger
                              : AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: isError ? 1 : 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isError)
                      Icon(
                        _toolExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: AppColors.danger,
                      ),
                  ],
                ),
                if (isError && _toolExpanded) ...[
                  const SizedBox(height: 8),
                  Divider(height: 1, color: AppColors.danger.withOpacity(0.4)),
                  const SizedBox(height: 8),
                  SelectableText(
                    widget.message.content,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: widget.message.content),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制')),
                        );
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_rounded, size: 12, color: AppColors.danger),
                          SizedBox(width: 4),
                          Text('复制',
                              style:
                                  TextStyle(color: AppColors.danger, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          borderRadius: isUser ? 22 : 18,
          backgroundOpacity: isUser ? 0.16 : 0.10,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.message.isStreaming && widget.message.content.isEmpty)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PulsingDot(size: 8, color: AppColors.accent2),
                    SizedBox(width: 6),
                    Text('思考中...',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 13)),
                  ],
                )
              else
                Text(
                  widget.message.content,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
