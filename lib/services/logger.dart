import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class LogEntry {
  final DateTime time;
  final String level;
  final String tag;
  final String message;
  LogEntry(this.time, this.level, this.tag, this.message);

  @override
  String toString() {
    String two(int n) => n.toString().padLeft(2, '0');
    final ts = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    return '$ts [$level] $tag: $message';
  }
}

class Log {
  static const String _appTag = 'PROMPTEUR';
  static final List<LogEntry> _buffer = [];
  static const int _maxBuffer = 500;

  static void d(String tag, String msg) => _log('D', tag, msg);
  static void i(String tag, String msg) => _log('I', tag, msg);
  static void w(String tag, String msg) => _log('W', tag, msg);

  static void e(String tag, String msg, [Object? error, StackTrace? st]) {
    final full = error != null ? '$msg | $error' : msg;
    _log('E', tag, full);
    if (kDebugMode && st != null) {
      developer.log('STACK', name: '$_appTag/$tag', error: error, stackTrace: st);
    }
  }

  static void _log(String lvl, String tag, String msg) {
    final entry = LogEntry(DateTime.now(), lvl, tag, msg);
    _buffer.add(entry);
    if (_buffer.length > _maxBuffer) _buffer.removeAt(0);
    if (kDebugMode) {
      developer.log('[$lvl] $msg', name: '$_appTag/$tag');
    }
  }

  static List<LogEntry> recent() => List.unmodifiable(_buffer);
  static void clear() => _buffer.clear();
}
