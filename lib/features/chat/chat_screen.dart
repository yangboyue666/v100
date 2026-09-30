import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/colors.dart';
import '../../core/providers.dart';
import '../../shared/widgets/glass_app_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/section_indicator.dart';
import '../../shared/widgets/animated_indicators.dart';
import '../../core/llm/llm_service.dart';
import '../../core/llm/model_manager.dart';
import '../model/ai_model_screen.dart';
import 'chat_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.embedded = false});

  /// true 表示嵌入在主界面中央，不显示自己的 AppBar
  final bool embedded;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatMessagesProvider.notifier).ensureSession();
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
      await ref.read(chatMessagesProvider.notifier).send(text);
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

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);
    if (messages.isNotEmpty) _scrollToBottom();

    if (widget.embedded) {
      return Column(
        children: [
          Expanded(child: _buildMessages(messages)),
          _buildInput(),
        ],
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: 'AI 助手',
        actions: [
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: const SectionIndicator(
                    label: '任务式助手',
                    colors: [AppColors.accent1, AppColors.accent2],
                  ),
                ),
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
      return SingleChildScrollView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const PulsingDot(size: 12, color: AppColors.accent1),
            const SizedBox(height: 10),
            Text(
              '我是你的本地 AI 助手',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: widget.embedded ? 15 : 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '完全离线运行，不会上传你的数据。\n试试说："明天下午3点开会"',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: widget.embedded ? 12 : 13,
              ),
            ),
            const SizedBox(height: 14),
            _QuickPrompts(embedded: widget.embedded),
            const SizedBox(height: 8),
          ],
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
                    hintText: '说点什么吧...',
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
              subtitle: const Text('自然语言解析为日程并提醒'),
              onTap: () {
                Navigator.pop(ctx);
                _inputCtrl.text = '明天下午3点开会';
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.assignment_rounded, color: AppColors.accent3),
              title: const Text('添加作业'),
              subtitle: const Text('解析课程、标题、截止日期'),
              onTap: () {
                Navigator.pop(ctx);
                _inputCtrl.text = '后天交《高等数学》第3章习题';
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_week_rounded, color: AppColors.accent4),
              title: const Text('添加课程'),
              subtitle: const Text('解析星期、节次、教室'),
              onTap: () {
                Navigator.pop(ctx);
                _inputCtrl.text = '周一第3节有《英语》课，教室A201';
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.memory_rounded, color: AppColors.accent1),
              title: const Text('AI 模型管理'),
              subtitle: const Text('下载 / 管理端侧千问模型'),
              onTap: () {
                Navigator.pop(ctx);
                _openModelManager();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 模型状态轻提示：仅在模型加载中时显示一行，不占用对话历史空间
class _ModelStatusHint extends ConsumerStatefulWidget {
  final ChatMode mode;

  const _ModelStatusHint({required this.mode});

  @override
  ConsumerState<_ModelStatusHint> createState() => _ModelStatusHintState();
}

class _ModelStatusHintState extends ConsumerState<_ModelStatusHint> {
  ModelStatus _status = ModelManager.instance.status;

  @override
  void initState() {
    super.initState();
    _status = ModelManager.instance.status;
    ModelManager.instance.statusStream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == ChatMode.normal) return const SizedBox.shrink();
    if (_status != ModelStatus.loading) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent1),
          ),
          SizedBox(width: 8),
          Text(
            '千问模型加载中，请稍候…',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 左上角模式切换下拉
class _ModeToggle extends ConsumerWidget {
  final ChatMode mode;
  final bool modelDownloaded;

  const _ModeToggle({required this.mode, required this.modelDownloaded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isModelMode = mode == ChatMode.downloadedModel;
    final canUseModel = modelDownloaded;

    return PopupMenuButton<ChatMode>(
      onSelected: (m) {
        ref.read(chatModeProvider.notifier).state = m;
      },
      tooltip: '切换对话模式',
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.15), width: 1),
      ),
      color: const Color(0xFF241442),
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isModelMode ? Icons.auto_awesome_rounded : Icons.chat_bubble_rounded,
              size: 14,
              color: isModelMode ? AppColors.accent2 : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              isModelMode ? '千问模型' : '普通模式',
              style: TextStyle(
                color: isModelMode ? AppColors.accent2 : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 12,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem<ChatMode>(
          value: ChatMode.normal,
          height: 36,
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Text(
                '普通模式',
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
              ),
              const Spacer(),
              if (mode == ChatMode.normal)
                const Icon(Icons.check, size: 14, color: AppColors.accent2),
            ],
          ),
        ),
        PopupMenuItem<ChatMode>(
          value: ChatMode.downloadedModel,
          height: 36,
          enabled: canUseModel,
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: canUseModel ? AppColors.accent1 : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                canUseModel ? '千问模型' : '千问模型（未下载）',
                style: TextStyle(
                  fontSize: 13,
                  color: canUseModel ? AppColors.textPrimary : AppColors.textMuted,
                ),
              ),
              if (!canUseModel) ...[
                const Spacer(),
                const Icon(Icons.download_rounded, size: 14, color: AppColors.accent4),
              ],
              if (canUseModel && mode == ChatMode.downloadedModel) ...[
                const Spacer(),
                const Icon(Icons.check, size: 14, color: AppColors.accent2),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickPrompts extends StatelessWidget {
  const _QuickPrompts({this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final prompts = [
      ('明天下午3点开会', Icons.event_available_rounded, AppColors.accent2),
      ('后天交数学作业', Icons.assignment_rounded, AppColors.accent3),
      ('怎么学英语更高效？', Icons.school_rounded, AppColors.accent4),
      ('1+1等于几', Icons.calculate_rounded, AppColors.accent1),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: prompts
          .map((p) => Chip(
                label: Text(
                  p.$1,
                  style: TextStyle(fontSize: embedded ? 12 : 13),
                ),
                avatar: Icon(p.$2, size: embedded ? 14 : 16, color: p.$3),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ))
          .toList(),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final UIMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.role == 'user') {
      return Align(
        alignment: Alignment.centerRight,
        child: GlassCard(
          margin: const EdgeInsets.only(left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          borderRadius: 20,
          backgroundOpacity: 0.30,
          gradient: LinearGradient(
            colors: [
              AppColors.accent2.withOpacity(0.55),
              AppColors.accent3.withOpacity(0.55),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Text(
            message.content,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ),
      );
    }
    if (message.role == 'tool') {
      // 工具结果展示
      return Align(
        alignment: Alignment.centerLeft,
        child: GlassCard(
          margin: const EdgeInsets.only(right: 60),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          borderRadius: 16,
          backgroundOpacity: 0.06,
          borderOpacity: 0.25,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.success),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  message.content,
                  style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // assistant
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.accent1, AppColors.accent2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent1.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: GlassCard(
              margin: const EdgeInsets.only(right: 40),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              borderRadius: 20,
              backgroundOpacity: 0.12,
              child: message.isStreaming && message.content.isEmpty
                  ? const WaveIndicator(height: 20, barCount: 4, barWidth: 3, color: AppColors.accent1)
                  : Text(
                      message.content,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        height: 1.55,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
