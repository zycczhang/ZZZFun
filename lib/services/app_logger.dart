import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String scope;
  final String message;
  final String? error;
  final String? stackTrace;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.scope,
    required this.message,
    this.error,
    this.stackTrace,
  });

  String get line {
    final time = timestamp.toLocal().toIso8601String().replaceFirst('T', ' ');
    final suffix = error == null ? '' : ' | $error';
    return '${time.substring(0, 19)} [${level.name.toUpperCase()}] [$scope] $message$suffix';
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'scope': scope,
    'message': message,
    'error': error,
    'stackTrace': stackTrace,
  };

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      level: LogLevel.values.firstWhere(
        (item) => item.name == json['level'],
        orElse: () => LogLevel.info,
      ),
      scope: json['scope']?.toString() ?? 'app',
      message: json['message']?.toString() ?? '',
      error: json['error']?.toString(),
      stackTrace: json['stackTrace']?.toString(),
    );
  }
}

class AppLogger {
  static const _storageKey = 'zzzfun_logs';
  static const _maxEntries = 300;
  static final ValueNotifier<List<LogEntry>> entries = ValueNotifier(const []);
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          entries.value = decoded
              .whereType<Map>()
              .map((item) => LogEntry.fromJson(Map<String, dynamic>.from(item)))
              .toList();
        }
      }
    } catch (error, stackTrace) {
      _write(
        LogLevel.warning,
        'logger',
        '读取历史日志失败',
        error,
        stackTrace,
        persist: false,
      );
    }
  }

  static void debug(
    String scope,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _write(LogLevel.debug, scope, message, error, stackTrace);
  }

  static void info(
    String scope,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _write(LogLevel.info, scope, message, error, stackTrace);
  }

  static void warning(
    String scope,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _write(LogLevel.warning, scope, message, error, stackTrace);
  }

  static void error(
    String scope,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _write(LogLevel.error, scope, message, error, stackTrace);
  }

  static Future<void> clear() async {
    entries.value = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      info('logger', '日志已清空');
    } catch (error, stackTrace) {
      _write(
        LogLevel.error,
        'logger',
        '清空日志失败',
        error,
        stackTrace,
        persist: false,
      );
    }
  }

  static String exportText() =>
      entries.value.map((entry) => entry.line).join('\n');

  static void _write(
    LogLevel level,
    String scope,
    String message,
    Object? error,
    StackTrace? stackTrace, {
    bool persist = true,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      scope: scope,
      message: message,
      error: error?.toString(),
      stackTrace: stackTrace?.toString(),
    );
    final next = [...entries.value, entry];
    entries.value = next.length > _maxEntries
        ? next.sublist(next.length - _maxEntries)
        : next;

    developer.log(
      message,
      name: 'ZZZFun.$scope',
      level: level.index * 300 + 500,
      error: error,
      stackTrace: stackTrace,
    );
    if (persist) _persist();
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(entries.value.map((entry) => entry.toJson()).toList()),
      );
    } catch (_) {
      // Logging must never make the application fail because storage is unavailable.
    }
  }
}
