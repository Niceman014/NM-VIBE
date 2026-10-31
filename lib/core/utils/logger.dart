import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Tiny tagged logger. Debug lines are stripped in release builds; warnings
/// and errors are always forwarded to the platform logger.
class AppLogger {
  const AppLogger(this.tag);

  final String tag;

  void d(String message) {
    if (kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }

  void i(String message) {
    if (kDebugMode) {
      debugPrint('[$tag] $message');
    }
    developer.log(message, name: tag);
  }

  void w(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: tag,
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void e(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: tag,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
