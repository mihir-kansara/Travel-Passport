import 'package:flutter/foundation.dart';

class AppLogger {
  static void info(
    String message, {
    String? name,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log('INFO', message, name: name, error: error, stackTrace: stackTrace);
  }

  static void error(
    String message, {
    String? name,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log('ERROR', message, name: name, error: error, stackTrace: stackTrace);
  }

  static void _log(
    String level,
    String message, {
    String? name,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer('[');
    buffer.write(level);
    buffer.write(']');
    if (name != null && name.isNotEmpty) {
      buffer.write('[');
      buffer.write(name);
      buffer.write(']');
    }
    buffer.write(' ');
    buffer.write(message);
    if (error != null) {
      buffer.write(' | ');
      buffer.write(error);
    }
    debugPrint(buffer.toString());
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }
}
