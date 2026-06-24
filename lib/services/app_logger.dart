import 'package:flutter/foundation.dart';

class AppLogger {
  const AppLogger._();

  static void debug(String scope, String message) {
    debugPrint('[Xylos][$scope] $message');
  }

  static void error(
    String scope,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    debugPrint('[Xylos][$scope][ERROR] $message');
    if (error != null) {
      debugPrint('[Xylos][$scope][ERROR] $error');
    }
    if (stackTrace != null) {
      debugPrintStack(
        label: '[Xylos][$scope][STACK]',
        stackTrace: stackTrace,
      );
    }
  }

  static String preview(String value, {int maxLength = 500}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}...';
  }
}
