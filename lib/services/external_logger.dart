// Minimal logger shim for the ported external book sources (Anna's Archive
// / LibGen, from warreth/OpenlibExtended). OpenlibExtended's logger writes
// to a rolling file and shares logs; zlibx keeps it debugPrint-only —
// no file_picker / path_provider / share_plus needed.
//
// This is NOT a port of OpenlibExtended's lib/services/logger.dart; it only
// provides the AppLogger API surface that the ported files call, plus
// createDioWithLogging (used by SlumCatalogue).

// Package imports:
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'http_client.dart';

/// A minimal stand-in for OpenlibExtended's AppLogger: the ported services
/// only need the four level methods plus a way to build a Dio that logs.
/// Single shared instance so the static-ish call sites stay identical.
class AppLogger {
  static final AppLogger _instance = AppLogger._();
  factory AppLogger() => _instance;
  AppLogger._();

  void debug(
    String message, {
    String? tag,
    Map<String, dynamic>? metadata,
  }) {
    if (!kDebugMode) return;
    debugPrint(_format('DEBUG', tag, message, metadata));
  }

  void info(
    String message, {
    String? tag,
    Map<String, dynamic>? metadata,
  }) {
    debugPrint(_format('INFO', tag, message, metadata));
  }

  void warning(
    String message, {
    String? tag,
    dynamic error,
    Map<String, dynamic>? metadata,
  }) {
    debugPrint(_format('WARN', tag, message, metadata, error));
  }

  void error(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    debugPrint(_format('ERROR', tag, message, metadata, error));
    if (stackTrace != null && kDebugMode) debugPrint(stackTrace.toString());
  }

  String _format(
    String level,
    String? tag,
    String message,
    Map<String, dynamic>? metadata, [
    dynamic error,
  ]) {
    final buffer = StringBuffer('[$level]');
    if (tag != null) buffer.write('[$tag]');
    buffer.write(' $message');
    if (error != null) buffer.write(' | $error');
    if (metadata != null && metadata.isNotEmpty) buffer.write(' | $metadata');
    return buffer.toString();
  }
}

/// Builds a [Dio] wired with the same logging behaviour the ported
/// SlumCatalogue expects: request/response logging plus per-request timing.
/// (Mirrors OpenlibExtended's createDioWithLogging, minus the file log.)
///
/// The client itself is built by [createDio] (see http_client.dart) so
/// timeouts, headers and redirects stay in one place; only the timing
/// interceptors are added here. Logs carry host + method + status only,
/// never the full URL — LibGen links can carry a `key=` query parameter.
Dio createDioWithLogging({BaseOptions? options}) {
  final dio = createDio(
    connectTimeout: options?.connectTimeout ?? const Duration(seconds: 15),
    receiveTimeout: options?.receiveTimeout ?? const Duration(seconds: 30),
    headers: options?.headers,
  );
  if (options != null) {
    dio.options.followRedirects = options.followRedirects;
    dio.options.maxRedirects = options.maxRedirects;
  }
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (req, handler) {
        req.extra['request_time'] = DateTime.now().millisecondsSinceEpoch;
        handler.next(req);
      },
      onResponse: (resp, handler) {
        final start = resp.requestOptions.extra['request_time'] as int?;
        final ms = start == null
            ? -1
            : DateTime.now().millisecondsSinceEpoch - start;
        AppLogger().debug(
          'HTTP ${resp.statusCode} ${resp.requestOptions.method} '
          '${resp.requestOptions.uri.host} (${ms}ms)',
          tag: 'Dio',
        );
        handler.next(resp);
      },
      onError: (err, handler) {
        final start = err.requestOptions.extra['request_time'] as int?;
        final ms = start == null
            ? -1
            : DateTime.now().millisecondsSinceEpoch - start;
        AppLogger().warning(
          'HTTP error ${err.response?.statusCode} '
          '${err.requestOptions.method} ${err.requestOptions.uri.host} '
          '(${ms}ms)',
          tag: 'Dio',
          error: err.message,
        );
        handler.next(err);
      },
    ),
  );
  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(responseBody: false));
  }
  return dio;
}
