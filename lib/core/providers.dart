import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'llm/llm_service.dart';
import 'llm/pattern_llm_service.dart';
import 'llm/nobodywho_llm_service.dart';
import 'llm/model_manager.dart';

/// 对话模式
enum ChatMode {
  /// 普通模式：模式匹配基础 AI，任务式对话（日程/作业/课程管理）
  normal,

  /// 下载模型模式：千问端侧大模型，自由聊天 + 工具调用
  downloadedModel,
}

/// 当前对话模式（用户手动切换）
final chatModeProvider = StateProvider<ChatMode>((ref) {
  return ChatMode.normal;
});

/// 当前使用的 LLM 服务（普通模式）
final llmServiceProvider = Provider<LlmService>((ref) {
  return PatternBasedLlmService();
});

/// 千问模型服务（下载模型模式）
final nobodywhoLlmServiceProvider = Provider<LlmService>((ref) {
  return NobodyWhoLlmService();
});

/// 模式匹配后备服务
final patternLlmServiceProvider = Provider<LlmService>((ref) {
  return PatternBasedLlmService();
});

/// 模型管理器
final modelManagerProvider = Provider<ModelManager>((ref) {
  return ModelManager.instance;
});

/// 模型是否已下载
final modelDownloadedProvider = FutureProvider<bool>((ref) async {
  return ModelManager.instance.isModelDownloaded();
});
