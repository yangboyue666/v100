import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/llm/ai_tools.dart';
import '../../core/llm/llm_service.dart';
import '../../core/llm/pattern_llm_service.dart';
import '../../core/llm/nobodywho_llm_service.dart';
import '../../core/llm/model_manager.dart';
import '../../core/providers.dart';
import '../schedule/schedule_controller.dart' as sch_ctrl;
import '../schedule/schedule_repository.dart';
import '../schedule/schedule_models.dart' as sch;
import '../assignments/assignments_controller.dart' as asg_ctrl;
import '../assignments/assignments_repository.dart';
import '../assignments/assignments_models.dart' as asg;
import '../courses/courses_controller.dart' as crs_ctrl;
import '../courses/courses_repository.dart';
import '../courses/courses_models.dart' as crs;
import 'chat_models.dart';
import 'chat_repository.dart';

/// UI 用的消息对象（包含流式状态）
class UIMessage {
  final String id;
  final String role;
  final String content;
  final List<LlmToolCall>? toolCalls;
  final String? toolResult;
  final bool isStreaming;
  final DateTime createdAt;

  UIMessage({
    required this.id,
    required this.role,
    required this.content,
    this.toolCalls,
    this.toolResult,
    this.isStreaming = false,
    required this.createdAt,
  });

  UIMessage copyWith({
    String? content,
    List<LlmToolCall>? toolCalls,
    String? toolResult,
    bool? isStreaming,
  }) {
    return UIMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      toolCalls: toolCalls ?? this.toolCalls,
      toolResult: toolResult ?? this.toolResult,
      isStreaming: isStreaming ?? this.isStreaming,
      createdAt: createdAt,
    );
  }
}

/// 当前活跃会话 ID
final currentSessionIdProvider = StateProvider<String?>((ref) => null);

/// 嵌入式聊天（首页底部，普通模式 — 任务式，添加日程/作业/课程）
final chatMessagesProvider =
    StateNotifierProvider<ChatMessagesNotifier, List<UIMessage>>((ref) {
  return ChatMessagesNotifier(ref, mode: ChatMode.normal);
});

/// 全屏 AI 聊天（AI 助手卡片，千问模型 — 自由聊天 + 工具调用）
final aiChatMessagesProvider =
    StateNotifierProvider<ChatMessagesNotifier, List<UIMessage>>((ref) {
  return ChatMessagesNotifier(ref, mode: ChatMode.downloadedModel);
});

class ChatMessagesNotifier extends StateNotifier<List<UIMessage>> {
  ChatMessagesNotifier(Ref ref, {required this.mode}) : _ref = ref, super([]);
  final Ref _ref;
  final ChatMode mode;
  final _uuid = const Uuid();

  String? _sessionId;

  Future<void> ensureSession() async {
    if (_sessionId != null) return;
    final s = await ChatRepository.instance.createSession();
    _sessionId = s.id;
    _ref.read(currentSessionIdProvider.notifier).state = s.id;
    state = [];
  }

  Future<void> loadSession(String sessionId) async {
    _sessionId = sessionId;
    _ref.read(currentSessionIdProvider.notifier).state = sessionId;
    final msgs = await ChatRepository.instance.messagesForSession(sessionId);
    state = msgs
        .map((m) => UIMessage(
              id: m.id,
              role: m.role,
              content: m.content,
              toolCalls: m.toolCalls,
              toolResult: m.toolResult,
              createdAt: m.createdAt,
            ))
        .toList();
  }

  Future<void> newSession() async {
    await ensureSession();
    final s = await ChatRepository.instance.createSession();
    _sessionId = s.id;
    _ref.read(currentSessionIdProvider.notifier).state = s.id;
    state = [];
  }

  Future<void> clearCurrent() async {
    if (_sessionId == null) return;
    await ChatRepository.instance.clearSession(_sessionId!);
    state = [];
  }

  /// 发送一条用户消息，触发流式回复
  Future<void> send(String text) async {
    await ensureSession();
    final sid = _sessionId!;

    // 1) 添加用户消息
    final userMsg = StoredChatMessage(
      id: _uuid.v4(),
      sessionId: sid,
      role: 'user',
      content: text,
      createdAt: DateTime.now(),
    );
    await ChatRepository.instance.addMessage(userMsg);
    state = [
      ...state,
      UIMessage(
        id: userMsg.id,
        role: 'user',
        content: text,
        createdAt: userMsg.createdAt,
      ),
    ];

    // 2) 创建占位 assistant 消息（流式）
    final assistantId = _uuid.v4();
    final startedAt = DateTime.now();
    state = [
      ...state,
      UIMessage(
        id: assistantId,
        role: 'assistant',
        content: '',
        isStreaming: true,
        createdAt: startedAt,
      ),
    ];

    // 3) 构造 LLM 输入（系统提示 + 历史）
    final history = await ChatRepository.instance.buildLlmMessages(sid);
    final llmMessages = <LlmMessage>[
      LlmMessage.system(AiTools.systemPrompt),
      ...history,
    ];

    // 4) 按模式选择后端（嵌入式=普通模型，全屏=千问模型）
    final allTools = AiTools.all();
    String fullText;
    bool usedRealModel = false;

    if (mode == ChatMode.downloadedModel) {
      try {
        fullText = await _streamAssistant(
          NobodyWhoLlmService(),
          llmMessages,
          allTools,
          assistantId,
        );
        usedRealModel = true;
      } catch (e) {
        ModelManager.instance.markError(e.toString());
        usedRealModel = false;
        fullText = await _streamAssistant(
          PatternBasedLlmService(),
          llmMessages,
          allTools,
          assistantId,
        );
      }
    } else {
      fullText = await _streamAssistant(
        PatternBasedLlmService(),
        llmMessages,
        allTools,
        assistantId,
      );
    }

    // 5) 真实模型（nobodywho）内部已处理工具调用，直接显示文本
    if (usedRealModel) {
      final assistantMsg = StoredChatMessage(
        id: assistantId,
        sessionId: sid,
        role: 'assistant',
        content: fullText,
        createdAt: startedAt,
      );
      await ChatRepository.instance.addMessage(assistantMsg);

      state = [
        for (final m in state)
          if (m.id == assistantId)
            m.copyWith(content: fullText, isStreaming: false)
          else
            m,
      ];
      return;
    }

    // 模式匹配模式：解析 <<TOOLCALL>> 标记
    final toolCalls = ToolCallParser.extract(fullText);
    final displayText = ToolCallParser.stripToolCalls(fullText);
    final hasToolCalls = toolCalls.isNotEmpty;

    String? toolResultText;
    if (hasToolCalls) {
      final results = <String>[];
      for (final tc in toolCalls) {
        final result = await _executeTool(tc);
        results.add(result);
      }
      toolResultText = results.join('\n');
    }

    final assistantMsg = StoredChatMessage(
      id: assistantId,
      sessionId: sid,
      role: 'assistant',
      content: fullText,
      toolCalls: hasToolCalls ? toolCalls : null,
      createdAt: startedAt,
    );
    await ChatRepository.instance.addMessage(assistantMsg);

    if (hasToolCalls) {
      final toolMsg = StoredChatMessage(
        id: _uuid.v4(),
        sessionId: sid,
        role: 'tool',
        content: toolResultText ?? '',
        toolResult: toolResultText,
        createdAt: DateTime.now(),
      );
      await ChatRepository.instance.addMessage(toolMsg);
    }

    state = [
      for (final m in state)
        if (m.id == assistantId)
          UIMessage(
            id: assistantId,
            role: 'assistant',
            content: displayText.isEmpty && hasToolCalls
                ? '已为你处理 ✓'
                : displayText,
            toolCalls: hasToolCalls ? toolCalls : null,
            toolResult: toolResultText,
            isStreaming: false,
            createdAt: startedAt,
          )
        else
          m,
      if (hasToolCalls)
        UIMessage(
          id: _uuid.v4(),
          role: 'tool',
          content: toolResultText ?? '',
          createdAt: DateTime.now(),
        ),
    ];
  }

  /// 将某个 LLM 的流式输出实时写入指定的 assistant 占位消息，返回完整文本
  Future<String> _streamAssistant(
    LlmService llm,
    List<LlmMessage> llmMessages,
    List<LlmTool> tools,
    String assistantId,
  ) async {
    final buf = StringBuffer();
    await for (final chunk in llm.stream(llmMessages, tools: tools)) {
      buf.write(chunk);
      state = [
        for (final m in state)
          if (m.id == assistantId)
            m.copyWith(content: buf.toString(), isStreaming: true)
          else
            m,
      ];
    }
    return buf.toString();
  }

  Future<String> _executeTool(LlmToolCall tc) async {
    final args = tc.parseArguments() ?? {};
    switch (tc.name) {
      case 'create_schedule':
        final s = sch.scheduleFromToolArgs(args);
        if (s == null) return '参数无效';
        final created = await ScheduleRepository.instance.create(s);
        _ref.invalidate(sch_ctrl.scheduleListProvider);
        return '已创建日程「${created.title}」，时间：${created.datetime.month}/${created.datetime.day} ${created.shortTime}';
      case 'list_schedules':
        final range = args['range']?.toString() ?? 'all';
        final list = range == 'today'
            ? await ScheduleRepository.instance.byDay(DateTime.now())
            : range == 'this_week'
                ? await ScheduleRepository.instance.thisWeek()
                : await ScheduleRepository.instance.all();
        if (list.isEmpty) return '当前没有日程';
        return list.map((s) => '· ${s.title}（${s.relativeDescription}）').join('\n');
      case 'complete_schedule':
        final id = args['id']?.toString();
        if (id == null) return '缺少 id';
        await ScheduleRepository.instance.markDone(id);
        _ref.invalidate(sch_ctrl.scheduleListProvider);
        return '已标记为完成';
      case 'delete_schedule':
        final id = args['id']?.toString();
        if (id == null) return '缺少 id';
        await ScheduleRepository.instance.delete(id);
        _ref.invalidate(sch_ctrl.scheduleListProvider);
        return '已删除';
      case 'create_assignment':
        final a = asg.assignmentFromToolArgs(args);
        if (a == null) return '参数无效';
        final created = await AssignmentRepository.instance.create(a);
        _ref.invalidate(asg_ctrl.assignmentListProvider);
        return '已添加作业《${created.course}》${created.title}';
      case 'list_assignments':
        final list = await AssignmentRepository.instance.all();
        if (list.isEmpty) return '当前没有作业';
        return list.take(10).map((a) => '· 《${a.course}》${a.title} - ${a.dueLabel}').join('\n');
      case 'update_assignment_progress':
        final id = args['id']?.toString();
        if (id == null) return '缺少 id';
        final progress = args['progress'] as int? ?? 0;
        await AssignmentRepository.instance.updateProgress(id, progress);
        _ref.invalidate(asg_ctrl.assignmentListProvider);
        return '已更新进度 $progress%';
      case 'add_course':
        final c = crs.courseFromToolArgs(args);
        if (c == null) return '参数无效';
        final created = await CourseRepository.instance.create(c);
        _ref.invalidate(crs_ctrl.coursesProvider);
        return '已添加课程「${created.name}」（${created.weekdayLabel} 第${created.period}节）';
      case 'list_courses':
        final list = await CourseRepository.instance.all();
        if (list.isEmpty) return '课程表为空';
        return list.map((c) => '· ${c.name}（${c.weekdayLabel} 第${c.period}节）${c.location ?? ''}').join('\n');
      default:
        return '未知工具：${tc.name}';
    }
  }
}
