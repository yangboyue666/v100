import 'dart:async';

import 'package:nobodywho/nobodywho.dart' as nobodywho;

import '../../features/schedule/schedule_repository.dart';
import '../../features/schedule/schedule_models.dart' as sch;
import '../../features/assignments/assignments_repository.dart';
import '../../features/assignments/assignments_models.dart' as asg;
import '../../features/courses/courses_repository.dart';
import '../../features/courses/courses_models.dart' as crs;
import '../utils/nl_datetime_parser.dart';
import '../utils/app_log.dart';
import 'llm_service.dart';
import 'model_manager.dart';

/// 基于 nobodywho（llama.cpp）的真实端侧 LLM 服务
///
/// - 加载用户选中的 Qwen3 GGUF 模型（单例，模型只加载一次并常驻）
/// - 使用 complete() 传入完整对话历史，保证多轮上下文连贯
/// - 支持 nobodywho 原生函数调用（create_schedule / create_assignment / add_course 等）
/// - 仅对支持工具调用格式的模型（Qwen3 等）注册 tools，其余模型走纯聊天
/// - Qwen3 关闭 thinking（enable_thinking=false），否则思考内容会干扰工具调用语法
/// - 加载失败时按 GPU→CPU、带工具→纯聊天的顺序回退
class NobodyWhoLlmService implements LlmService {
  NobodyWhoLlmService._();

  static final NobodyWhoLlmService instance = NobodyWhoLlmService._();

  factory NobodyWhoLlmService() => instance;

  nobodywho.Chat? _chat;
  String? _loadedModelId;
  bool _initialized = false;
  bool _toolsEnabled = false;
  Future<void>? _loading;

  static const Duration loadTimeout = Duration(minutes: 5);

  /// 当前会话是否启用了原生工具调用
  bool get toolsEnabled => _toolsEnabled;

  @override
  Future<bool> isReady() async {
    if (!await ModelManager.instance.isModelDownloaded()) return false;
    return _initialized && _chat != null;
  }

  bool get isLoaded => _chat != null;

  @override
  String describe() => '本地端侧模型 · 真实推理（nobodywho / llama.cpp）';

  /// 确保当前选中模型已加载（幂等，并发安全，模型切换时重新加载）
  Future<void> ensureLoaded() {
    return _loading ??= _loadIfNeeded().whenComplete(() => _loading = null);
  }

  Future<void> _loadIfNeeded() async {
    final model = await ModelManager.instance.currentModel;
    if (!await ModelManager.instance.isModelDownloaded(model.id)) {
      throw Exception('当前模型未下载，请在 AI 模型页下载模型');
    }
    if (_chat != null && _loadedModelId == model.id) return;
    if (_chat != null) {
      await dispose();
    }
    await _loadChat(model);
  }

  Future<void> _loadChat(ModelInfo model) async {
    final path = await ModelManager.instance.modelPath(model.id);
    ModelManager.instance.markLoading();
    AppLog.instance.info('开始加载模型：${model.displayName}（工具=${model.supportsTools}）');

    // 加载策略（最多 3 次）：
    // 1) 支持工具的模型：带工具 + GPU
    // 2)                 带工具 + CPU（排除 GPU 因素）
    // 3)                 纯聊天 + GPU（排除工具格式因素；不支持工具的模型直接走这里）
    final plans = <(bool, bool)>[
      (model.supportsTools, true),
      (model.supportsTools, false),
      if (model.supportsTools) (false, true),
    ];

    Object? lastError;
    for (final (withTools, useGpu) in plans) {
      try {
        final chat = await _createChat(path, useGpu: useGpu, withTools: withTools);
        _chat = chat;
        _toolsEnabled = withTools;
        _initialized = true;
        _loadedModelId = model.id;
        ModelManager.instance.markRunning();
        AppLog.instance.info(
            '模型加载成功：${model.displayName}（工具=$withTools, GPU=$useGpu）');
        return;
      } catch (e, st) {
        lastError = e;
        AppLog.instance.error('加载失败（工具=$withTools, GPU=$useGpu）', e, st);
      }
    }

    _chat = null;
    _initialized = false;
    _loadedModelId = null;
    _toolsEnabled = false;
    final message = _friendlyError(lastError);
    ModelManager.instance.markError(message);
    throw Exception(message);
  }

  /// 把底层英文异常转成用户能看懂的中文提示
  String _friendlyError(Object? error) {
    final s = error?.toString() ?? '未知错误';
    if (s.contains("doesn't support tool calling") ||
        s.contains('NoToolTemplate') ||
        s.contains('Unsupported tool calling format') ||
        s.contains('tool calling format')) {
      return '该模型不支持工具调用（日程/作业/课程）。已尝试回退纯聊天，若仍失败请改用 Qwen3 系列模型。';
    }
    if (s.contains('chat template') || s.contains('ChatTemplate')) {
      return '该 GGUF 文件缺少对话模板，请改用官方 Qwen3-GGUF 模型。';
    }
    if (s.contains('memory') ||
        s.contains('Memory') ||
        s.contains('bad_alloc') ||
        s.contains('OutOfMemory')) {
      return '内存不足，无法加载该模型。请换用更小的模型（如 Qwen3 0.6B）。';
    }
    if (s.contains('Model not found') || s.contains('not found')) {
      return '模型文件未找到，请重新下载。';
    }
    return '模型加载失败：$s';
  }

  Future<nobodywho.Chat> _createChat(String modelPath,
      {required bool useGpu, required bool withTools}) async {
    // 仅在需要工具时才构造 Tool 对象——nobodywho 在构造 Tool 时即解析函数签名，
    // 纯聊天模式构造任何 Tool 都可能触发签名解析异常。
    final tools = withTools ? _buildTools() : const <nobodywho.Tool>[];

    AppLog.instance.info('创建 Chat：tools=$withTools, gpu=$useGpu');
    return await nobodywho.Chat.fromPath(
      modelPath: modelPath,
      systemPrompt: withTools ? _toolSystemPrompt : _chatSystemPrompt,
      tools: tools,
      contextSize: 4096,
      useGpu: useGpu,
      // Qwen3 等 thinking 模型必须关闭思考，否则思考内容会干扰工具调用的语法约束
      templateVariables: const {'enable_thinking': false},
    ).timeout(loadTimeout);
  }

  /// 构建工具列表（仅在模型支持工具调用时调用）
  ///
  /// nobodywho 4.0.0 解析工具函数签名时不支持可空类型（String?/int?），
  /// 可选参数必须用非空类型 + 默认值。
  List<nobodywho.Tool> _buildTools() {
    final createScheduleTool = nobodywho.Tool(
      name: 'create_schedule',
      description:
          '创建一条日程提醒。当用户明确表达"明天下午3点开会"等安排时调用。'
          'datetime 必须是 ISO8601 格式字符串，如 2026-09-30T15:00:00。',
      function: ({
        required String title,
        required String datetime,
        int remind_before = 600,
        String note = '',
      }) async {
        try {
          final dt = DateTime.tryParse(datetime) ??
              NLDateTimeParser.parse(datetime) ??
              DateTime.now();
          final s = sch.Schedule.create(
            id: '',
            title: title,
            datetime: dt,
            remindBefore: remind_before,
            note: note,
          );
          final created = await ScheduleRepository.instance.create(s);
          return '已创建日程「${created.title}」，时间：${created.datetime.month}月${created.datetime.day}日 ${created.shortTime}';
        } catch (e) {
          return '创建日程失败：$e';
        }
      },
      parameterDescriptions: {
        'title': '日程标题，简短描述',
        'datetime': 'ISO8601 格式的日期时间',
        'remind_before': '提前多少秒提醒，默认 600（10分钟）',
        'note': '备注，可选，无则传空字符串',
      },
    );

    final createAssignmentTool = nobodywho.Tool(
      name: 'create_assignment',
      description:
          '创建一条作业。status 可选 not_started / in_progress / completed，'
          'progress 为 0-100 的整数。due_date 为 ISO8601 格式。',
      function: ({
        required String course,
        required String title,
        required String due_date,
        String status = 'not_started',
        int progress = 0,
      }) async {
        try {
          final due = DateTime.tryParse(due_date) ??
              NLDateTimeParser.parse(due_date) ??
              DateTime.now().add(const Duration(days: 3));
          final a = asg.Assignment.create(
            id: '',
            course: course,
            title: title,
            dueDate: due,
            status: asg.AssignmentStatus.fromCode(status),
            progress: progress,
            notes: '',
          );
          final created = await AssignmentRepository.instance.create(a);
          return '已创建作业「${created.title}」（${created.course}），截止：${created.dueDate.month}/${created.dueDate.day}';
        } catch (e) {
          return '创建作业失败：$e';
        }
      },
      parameterDescriptions: {
        'course': '课程名称',
        'title': '作业标题',
        'due_date': 'ISO8601 截止时间',
        'status': '状态：not_started / in_progress / completed',
        'progress': '进度 0-100',
      },
    );

    final addCourseTool = nobodywho.Tool(
      name: 'add_course',
      description: '添加一条课程到课程表。weekday: 1=周一..7=周日，period: 第几节。',
      function: ({
        required String name,
        required int weekday,
        required int period,
        String location = '',
        String teacher = '',
      }) async {
        try {
          final c = crs.Course.create(
            id: '',
            name: name,
            weekday: weekday,
            period: period,
            location: location,
            teacher: teacher,
          );
          final created = await CourseRepository.instance.create(c);
          return '已添加课程「${created.name}」，周${['一', '二', '三', '四', '五', '六', '日'][created.weekday - 1]}第${created.period}节';
        } catch (e) {
          return '添加课程失败：$e';
        }
      },
      parameterDescriptions: {
        'name': '课程名称',
        'weekday': '星期几，1=周一..7=周日',
        'period': '第几节课',
        'location': '教室地点',
        'teacher': '授课教师',
      },
    );

    final listSchedulesTool = nobodywho.Tool(
      name: 'list_schedules',
      description: '查询日程列表。range: today / this_week / all',
      function: ({String range = 'all'}) async {
        try {
          final List<sch.Schedule> all;
          if (range == 'today') {
            all = await ScheduleRepository.instance.byDay(DateTime.now());
          } else if (range == 'this_week') {
            all = await ScheduleRepository.instance.thisWeek();
          } else {
            all = await ScheduleRepository.instance.all();
          }
          if (all.isEmpty) return '暂无日程。';
          return all
              .map((s) =>
                  '· ${s.datetime.month}/${s.datetime.day} ${s.shortTime} ${s.title}${s.isDone ? '（已完成）' : ''}')
              .join('\n');
        } catch (e) {
          return '查询失败：$e';
        }
      },
      parameterDescriptions: {
        'range': '查询范围：today / this_week / all',
      },
    );

    final listAssignmentsTool = nobodywho.Tool(
      name: 'list_assignments',
      description: '查询作业列表。status: not_started / in_progress / completed / all',
      function: ({String status = 'all'}) async {
        try {
          final all = await AssignmentRepository.instance.all();
          final targetStatus = status == 'all'
              ? null
              : asg.AssignmentStatus.fromCode(status);
          final filtered = targetStatus == null
              ? all
              : all.where((a) => a.status == targetStatus).toList();
          if (filtered.isEmpty) return '暂无作业。';
          return filtered
              .map((a) =>
                  '· [${a.course}] ${a.title} 截止${a.dueDate.month}/${a.dueDate.day} 进度${a.progress}%')
              .join('\n');
        } catch (e) {
          return '查询失败：$e';
        }
      },
      parameterDescriptions: {
        'status': '作业状态筛选',
      },
    );

    return [
      createScheduleTool,
      createAssignmentTool,
      addCourseTool,
      listSchedulesTool,
      listAssignmentsTool,
    ];
  }

  /// 工具模式系统提示（原生工具调用，不要输出 <<TOOLCALL>> 文本标记）
  static const String _toolSystemPrompt = '''你是运行在用户手机上的学生智能助手，完全离线，数据不上传。

你是一个对话伙伴和学习助手：
- 用户聊天、提问、知识咨询、数学计算（如"cos 30度等于多少"、"1+1"、"你好"）→ 直接回答，不要调用工具。
- 用户明确要求创建/添加/记录日程、作业、课程时，才调用对应工具：
  · "明天下午3点开会" → create_schedule
  · "高数作业周五截止" → create_assignment
  · "周三第2节英语课" → add_course
- 用户询问已有日程/作业时，调用 list_schedules / list_assignments。

直接用自然语言回复，保持简洁、友好、使用中文。''';

  /// 纯聊天模式系统提示（模型不支持工具调用时）
  static const String _chatSystemPrompt = '''你是运行在用户手机上的学生智能助手，完全离线，数据不上传。

你是一个友好的对话伙伴和学习助手，可以陪用户聊天、解答知识问题、进行数学计算、分享学习方法。
直接回答用户的问题，保持简洁、友好、使用中文。''';

  /// 将 LlmMessage 列表转为 nobodywho 消息列表
  ///
  /// 规则（nobodywho 4.0.0 complete 的要求）：
  /// - system 已由 Chat.fromPath 设置，且 complete 要求 system 只能在首位，这里统一跳过；
  /// - tool 消息由 nobodywho 内部自动完成「调用→执行→回填」，历史中无需回传，跳过；
  /// - 列表必须非空且以 user 结尾，末尾多余的 assistant 会被丢弃。
  List<nobodywho.Message> _toNobodyWhoMessages(List<LlmMessage> messages) {
    final out = <nobodywho.Message>[];
    final roles = <String>[];
    for (final m in messages) {
      if (m.role == 'user') {
        out.add(nobodywho.userMessage(m.content));
        roles.add('user');
      } else if (m.role == 'assistant') {
        out.add(nobodywho.assistantMessage(m.content));
        roles.add('assistant');
      }
      // system / tool 跳过
    }
    while (roles.isNotEmpty && roles.last != 'user') {
      roles.removeLast();
      out.removeLast();
    }
    if (out.isEmpty) {
      out.add(nobodywho.userMessage('你好'));
    }
    return out;
  }

  @override
  Future<String> complete(
    List<LlmMessage> messages, {
    List<LlmTool> tools = const [],
  }) async {
    await ensureLoaded();
    final nwMessages = _toNobodyWhoMessages(messages);
    final buf = StringBuffer();
    await for (final token in _chat!.complete(nwMessages)) {
      buf.write(token);
    }
    return buf.toString();
  }

  @override
  Stream<String> stream(
    List<LlmMessage> messages, {
    List<LlmTool> tools = const [],
  }) async* {
    await ensureLoaded();
    final nwMessages = _toNobodyWhoMessages(messages);
    AppLog.instance.info(
        '开始推理（模型=$_loadedModelId, 工具=$_toolsEnabled, 消息数=${nwMessages.length}）');
    try {
      await for (final token in _chat!.complete(nwMessages)) {
        yield token;
      }
      AppLog.instance.info('推理完成');
    } catch (e, st) {
      AppLog.instance.error('推理过程异常', e, st);
      rethrow;
    }
  }

  /// 释放模型资源
  Future<void> dispose() async {
    _chat = null;
    _initialized = false;
    _loadedModelId = null;
    _toolsEnabled = false;
  }
}
