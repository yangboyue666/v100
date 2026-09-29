import 'dart:async';

import 'package:nobodywho/nobodywho.dart' as nobodywho;

import '../../features/schedule/schedule_repository.dart';
import '../../features/schedule/schedule_models.dart' as sch;
import '../../features/assignments/assignments_repository.dart';
import '../../features/assignments/assignments_models.dart' as asg;
import '../../features/courses/courses_repository.dart';
import '../../features/courses/courses_models.dart' as crs;
import '../utils/nl_datetime_parser.dart';
import 'llm_service.dart';
import 'model_manager.dart';

/// 基于 nobodywho（llama.cpp）的真实端侧 LLM 服务
///
/// - 加载用户选中的 Qwen3 GGUF 模型（单例，模型只加载一次并常驻）
/// - 使用 setChatHistory() + ask() 传入完整对话历史，保证多轮上下文连贯
/// - 支持原生函数调用（create_schedule / create_assignment / add_course 等）
/// - 加载失败时先尝试回退到 CPU 推理
class NobodyWhoLlmService implements LlmService {
  NobodyWhoLlmService._();

  static final NobodyWhoLlmService instance = NobodyWhoLlmService._();

  factory NobodyWhoLlmService() => instance;

  nobodywho.Chat? _chat;
  String? _loadedModelId;
  bool _initialized = false;
  Future<void>? _loading;

  static const Duration loadTimeout = Duration(minutes: 5);

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

    try {
      _chat = await _createChat(path, useGpu: true);
    } catch (_) {
      try {
        _chat = await _createChat(path, useGpu: false);
      } catch (e) {
        _chat = null;
        _initialized = false;
        _loadedModelId = null;
        ModelManager.instance.markError('模型加载失败：$e');
        rethrow;
      }
    }

    _initialized = true;
    _loadedModelId = model.id;
    ModelManager.instance.markRunning();
  }

  Future<nobodywho.Chat> _createChat(String modelPath,
      {required bool useGpu}) async {
    final createScheduleTool = nobodywho.Tool(
      name: 'create_schedule',
      description:
          '创建一条日程提醒。当用户明确表达"明天下午3点开会"等安排时调用。'
          'datetime 必须是 ISO8601 格式字符串，如 2026-09-30T15:00:00。',
      function: ({
        required String title,
        required String datetime,
        int? remind_before,
        String? note,
      }) async {
        try {
          final dt = DateTime.tryParse(datetime) ??
              NLDateTimeParser.parse(datetime) ??
              DateTime.now();
          final s = sch.Schedule.create(
            id: '',
            title: title,
            datetime: dt,
            remindBefore: remind_before ?? 600,
            note: note ?? '',
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
        'note': '备注，可选',
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
        String? status,
        int? progress,
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
            status: asg.AssignmentStatus.fromCode(status ?? 'not_started'),
            progress: progress ?? 0,
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
        String? location,
        String? teacher,
      }) async {
        try {
          final c = crs.Course.create(
            id: '',
            name: name,
            weekday: weekday,
            period: period,
            location: location ?? '',
            teacher: teacher ?? '',
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
      function: ({String? range}) async {
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
      function: ({String? status}) async {
        try {
          final all = await AssignmentRepository.instance.all();
          final targetStatus = status == null || status == 'all'
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

    return await nobodywho.Chat.fromPath(
      modelPath: modelPath,
      systemPrompt: _systemPrompt,
      tools: [
        createScheduleTool,
        createAssignmentTool,
        addCourseTool,
        listSchedulesTool,
        listAssignmentsTool,
      ],
      contextSize: 4096,
      useGpu: useGpu,
    ).timeout(loadTimeout);
  }

  static const String _systemPrompt = '''你是一个学生智能助手，运行在用户手机上，完全离线，数据不上传。

你首先是一个对话伙伴和学习助手。对于用户的提问、聊天、知识咨询、数学计算等，直接回答，不要调用工具。

只有当用户明确表达"帮我创建/添加/记录日程、作业、课程"等意图时，才调用对应工具：
- "明天下午3点开会" → 调用 create_schedule
- "高数作业截止周五" → 调用 create_assignment
- "周三第2节英语课" → 调用 add_course

对于"cos 30度等于多少"、"1+1等于几"、"你好"等问题，直接给出答案，不要调用工具。
保持回复简洁、友好，使用中文。''';

  /// 将 LlmMessage 列表转为 nobodywho 消息列表（传完整对话历史）
  ///
  /// 4.0.0 API：使用顶层函数 systemMessage/userMessage/assistantMessage
  List<nobodywho.Message> _toNobodyWhoMessages(List<LlmMessage> messages) {
    final out = <nobodywho.Message>[];
    for (final m in messages) {
      switch (m.role) {
        case 'system':
          out.add(nobodywho.systemMessage(m.content));
          break;
        case 'user':
          out.add(nobodywho.userMessage(m.content));
          break;
        case 'assistant':
          out.add(nobodywho.assistantMessage(m.content));
          break;
      }
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
    yield* _chat!.complete(nwMessages);
  }

  /// 释放模型资源
  Future<void> dispose() async {
    _chat = null;
    _initialized = false;
    _loadedModelId = null;
  }
}
