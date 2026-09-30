import 'dart:async';
import 'package:flutter/foundation.dart';

/// 日志条目（带时间戳，用于自动过期清理）
class _LogEntry {
  _LogEntry(this.time, this.level, this.message);
  final DateTime time;
  final String level;
  final String message;

  String get display {
    final now = time;
    final ts = '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    return '[$ts][$level] $message';
  }
}

/// 轻量内存日志：记录 AI 加载/推理过程的关键事件与异常。
///
/// - 仅在内存中保留最近 [retention] 时间（默认 24 小时）内的日志，过期自动删除。
/// - 「AI 助手」页右上角日志按钮可查看，用户可复制关键错误反馈给开发者。
class AppLog {
  AppLog._();
  static final AppLog instance = AppLog._();

  static const int _maxLines = 800;
  static const Duration retention = Duration(hours: 24);

  final List<_LogEntry> _entries = [];
  final StreamController<List<String>> _ctrl =
      StreamController<List<String>>.broadcast();

  List<String> get lines => List.unmodifiable(_entries.map((e) => e.display));
  Stream<List<String>> get stream => _ctrl.stream;

  void info(String message) => _add('INFO', message);

  void warn(String message) => _add('WARN', message);

  void error(String message, [Object? error, StackTrace? stack]) {
    final detail = error == null ? message : '$message — $error';
    _add('ERROR', detail);
    if (stack != null) debugPrint('[AppLog][ERROR] $message\n$error\n$stack');
  }

  void clear() {
    _entries.clear();
    _ctrl.add(const []);
  }

  void _add(String level, String message) {
    final now = DateTime.now();
    _entries.add(_LogEntry(now, level, message));
    // 自动清理超过保留时长的旧日志
    _entries.removeWhere((e) => now.difference(e.time) > retention);
    if (_entries.length > _maxLines) {
      _entries.removeRange(0, _entries.length - _maxLines);
    }
    _ctrl.add(lines);
    debugPrint('[AppLog][$level] $message');
  }
}