import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/colors.dart';
import '../../router/app_router.dart';
import '../../shared/widgets/glass_app_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/section_indicator.dart';
import '../../shared/widgets/shimmer_text.dart';
import '../../shared/widgets/animated_indicators.dart';
import '../chat/chat_screen.dart';
import '../chat/fullscreen_ai_screen.dart';
import '../model/ai_model_screen.dart';

class HubScreen extends ConsumerStatefulWidget {
  const HubScreen({super.key});

  @override
  ConsumerState<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends ConsumerState<HubScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  bool _chatExpanded = true;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    super.dispose();
  }

  void _toggleChat() {
    setState(() => _chatExpanded = !_chatExpanded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 背景渐变 + 浮动光晕
          Container(decoration: const BoxDecoration(gradient: appBackgroundGradient)),
          ..._buildFloatingOrbs(),
          // 主内容
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 顶部标题区
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Row(
                          children: [
                            const SectionIndicator(
                              label: '智能助手中心',
                              colors: [AppColors.accent1, AppColors.accent3],
                            ),
                            const Spacer(),
                            const PulsingDot(size: 7, color: AppColors.success),
                            const SizedBox(width: 6),
                            const Text(
                              '本地运行中',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GlassIconButton(
                              icon: const Icon(Icons.memory_rounded),
                              size: 34,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const AiModelScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 流光标题
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: ShimmerText(
                          text: '今天，让 AI 帮你',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            height: 1.1,
                          ),
                          duration: const Duration(seconds: 4),
                        ),
                      ),
                      Expanded(child: _buildLayout(constraints)),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayout(BoxConstraints constraints) {
    final isWide = constraints.maxWidth > 600;
    return isWide ? _wideLayout() : _narrowLayout();
  }

  /// 窄屏：3x2 网格（6 入口）+ 底部浮动 AI 圆球（可展开）
  Widget _narrowLayout() {
    return Column(
      children: [
        // 3x2 网格
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, c) {
              const gap = 12.0;
              final sizeW = ((c.maxWidth - gap) / 2).clamp(100.0, 200.0);
              final sizeH = ((c.maxHeight - 2 * gap) / 3).clamp(80.0, 200.0);
              final size = sizeW < sizeH ? sizeW : sizeH;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _EntryCard(size: size, entry: HubEntry.schedule),
                        const SizedBox(width: gap),
                        _EntryCard(size: size, entry: HubEntry.assignment),
                      ],
                    ),
                    const SizedBox(height: gap),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _EntryCard(size: size, entry: HubEntry.course),
                        const SizedBox(width: gap),
                        _EntryCard(size: size, entry: HubEntry.mood),
                      ],
                    ),
                    const SizedBox(height: gap),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _AiEntryCard(size: size),
                        const SizedBox(width: gap),
                        _ModelManageCard(size: size),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // 底部浮动 AI 圆球 / 展开对话框
        _buildBottomChat(),
      ],
    );
  }

  /// 底部浮动 AI：收起=圆球，展开=嵌入式对话框
  Widget _buildBottomChat() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomRight,
      child: _chatExpanded
          ? Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: SizedBox(
                height: 280,
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  borderRadius: 28,
                  backgroundOpacity: 0.10,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Column(
                      children: [
                        _buildChatHeader(),
                        const Expanded(child: ChatScreen(embedded: true)),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 16, 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildFloatingBall(),
              ),
            ),
    );
  }

  /// 浮动 AI 圆球
  Widget _buildFloatingBall() {
    return GestureDetector(
      onTap: _toggleChat,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.accent1, AppColors.accent2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent2.withOpacity(0.4),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(Icons.chat_rounded, color: Colors.white, size: 28),
      ),
    );
  }

  /// AI 对话框顶部栏：标题 + 折叠按钮
  Widget _buildChatHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.08), width: 1),
        ),
      ),
      child: Row(
        children: [
          const PulsingDot(size: 8, color: AppColors.accent1),
          const SizedBox(width: 8),
          const Text(
            'AI 助手',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _toggleChat,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.expand_more_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 宽屏：左右布局。左 6 入口竖排，右 AI 对话框
  Widget _wideLayout() {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...HubEntry.values.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _EntryCard(size: double.infinity, entry: e, horizontal: true),
                    )),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AiEntryCard(size: double.infinity, horizontal: true),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ModelManageCard(size: double.infinity, horizontal: true),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: GlassCard(
            padding: EdgeInsets.zero,
            borderRadius: 28,
            backgroundOpacity: 0.10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Column(
                children: [
                  _buildChatHeader(),
                  const Expanded(child: ChatScreen(embedded: true)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 浮动光晕
  List<Widget> _buildFloatingOrbs() {
    return [
      Positioned(
        top: -80,
        right: -60,
        child: AnimatedBuilder(
          animation: _floatCtrl,
          builder: (ctx, _) {
            final t = _floatCtrl.value;
            return Transform.translate(
              offset: Offset(-t * 20, t * 12),
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent2.withOpacity(0.25),
                      AppColors.accent2.withOpacity(0),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      Positioned(
        bottom: -100,
        left: -80,
        child: AnimatedBuilder(
          animation: _floatCtrl,
          builder: (ctx, _) {
            final t = _floatCtrl.value;
            return Transform.translate(
              offset: Offset(t * 16, -t * 8),
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent1.withOpacity(0.20),
                      AppColors.accent1.withOpacity(0),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }
}

enum HubEntry {
  schedule('日程', Icons.event_available_rounded, [AppColors.accent2, AppColors.accent3], AppRoutes.schedule),
  assignment('作业', Icons.assignment_turned_in_rounded, [AppColors.accent3, AppColors.accent1], AppRoutes.assignments),
  course('课程表', Icons.calendar_view_week_rounded, [AppColors.accent4, AppColors.accent1], AppRoutes.courses),
  mood('心情', Icons.mood_rounded, [AppColors.accent1, AppColors.accent2], AppRoutes.mood);

  const HubEntry(this.label, this.icon, this.colors, this.route);
  final String label;
  final IconData icon;
  final List<Color> colors;
  final String route;
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.size,
    required this.entry,
    this.horizontal = false,
  });

  final double size;
  final HubEntry entry;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    if (size == double.infinity || horizontal) {
      return GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: 24,
        backgroundOpacity: 0.12,
        onTap: () => AppRoutes.push(context, entry.route),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: entry.colors),
                shape: BoxShape.circle,
              ),
              child: Icon(entry.icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subtitleFor(entry),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      );
    }
    // 方形卡片
    return SizedBox(
      width: size,
      height: size,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        borderRadius: 24,
        backgroundOpacity: 0.10,
        onTap: () => AppRoutes.push(context, entry.route),
        child: Stack(
          children: [
            // 渐变背景
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      entry.colors.first.withOpacity(0.20),
                      entry.colors.last.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: entry.colors),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: entry.colors.first.withOpacity(0.4),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(entry.icon, color: Colors.white, size: 20),
                  ),
                  const Spacer(),
                  Text(
                    entry.label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subtitleFor(entry),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitleFor(HubEntry e) {
    switch (e) {
      case HubEntry.schedule:
        return '自然语言添加日程';
      case HubEntry.assignment:
        return '进度追踪与截止提醒';
      case HubEntry.course:
        return '周视图 + 课程表照片';
      case HubEntry.mood:
        return '记录心情 · 心情日历';
    }
  }
}

/// AI 助手卡片 → 全屏千问对话
class _AiEntryCard extends StatelessWidget {
  const _AiEntryCard({required this.size, this.horizontal = false});
  final double size;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final colors = [AppColors.accent1, AppColors.accent2];
    if (size == double.infinity || horizontal) {
      return GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: 24,
        backgroundOpacity: 0.14,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FullScreenAiScreen()),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI 助手', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('千问大模型 · 自由对话', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        borderRadius: 24,
        backgroundOpacity: 0.14,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FullScreenAiScreen()),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.first.withOpacity(0.25), colors.last.withOpacity(0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: colors),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: colors.first.withOpacity(0.4), blurRadius: 10, spreadRadius: 1)],
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                  ),
                  const Spacer(),
                  const Text('AI 助手', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('千问大模型\n自由对话', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 模型管理卡片 → 下载/管理端侧模型
class _ModelManageCard extends StatelessWidget {
  const _ModelManageCard({required this.size, this.horizontal = false});
  final double size;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final colors = [AppColors.accent4, AppColors.accent1];
    if (size == double.infinity || horizontal) {
      return GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: 24,
        backgroundOpacity: 0.12,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AiModelScreen()),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.memory_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('模型管理', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('下载/切换端侧模型', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        borderRadius: 24,
        backgroundOpacity: 0.12,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AiModelScreen()),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.first.withOpacity(0.20), colors.last.withOpacity(0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: colors),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: colors.first.withOpacity(0.4), blurRadius: 10, spreadRadius: 1)],
                    ),
                    child: const Icon(Icons.memory_rounded, color: Colors.white, size: 20),
                  ),
                  const Spacer(),
                  const Text('模型管理', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('下载/切换\n端侧模型', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
