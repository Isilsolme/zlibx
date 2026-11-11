// Single entry point for everything this app prints to the log.
//
// Logging used to be split three ways: bare `debugPrint` call sites
// (release-visible — `debugPrint` logs even in release mode, see
// flutter/foundation print.dart), `AppLogger` (the ported
// OpenlibExtended shim, debug-only), and `Diagnostics.record` /
// `logIgnored` (swallowed failures, exception type + timestamp only).
//
// Everything that PRINTS now routes through here, so the gating is
// visible in one place:
//
// * debug / info / warning / error — debug builds only, the same gate
//   `AppLogger` always had. Release gains no new output: the metadata
//   on these calls can carry the user's search query, per-book URLs
//   and response-body previews.
// * report — prints in all modes, exactly what a bare `debugPrint`
//   did. Only for messages whose content is release-safe (static
//   text, exception TYPEs, counts, hostnames). Anything that could
//   carry a token, cookie, password, session id, full URL with query,
//   search query or response-body preview must NOT go through report:
//   it goes through warning / error (debug-only) instead, redacted to
//   the exception type where it is still printed.
// * ignored — the `Diagnostics` record path (type + timestamp only),
//   unchanged. It is not a print path: the in-memory trail is what
//   Settings / bug reports dump.
import 'package:flutter/foundation.dart';

class AppLog {
  AppLog._();

  static void debug(
    String message, {
    String? tag,
    Map<String, dynamic>? metadata,
  }) {
    if (!kDebugMode) return;
    debugPrint(_format('DEBUG', tag, message, metadata, null));
  }

  static void info(
    String message, {
    String? tag,
    Map<String, dynamic>? metadata,
  }) {
    // Same gate as debug(): the metadata can carry the user's search
    // query, per-book URLs and response-body previews, readable by any
    // process holding READ_LOGS.
    if (!kDebugMode) return;
    debugPrint(_format('INFO', tag, message, metadata, null));
  }

  static void warning(
    String message, {
    String? tag,
    dynamic error,
    Map<String, dynamic>? metadata,
  }) {
    if (!kDebugMode) return;
    debugPrint(_format('WARN', tag, message, metadata, error));
  }

  static void error(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    if (!kDebugMode) return;
    debugPrint(_format('ERROR', tag, message, metadata, error));
    if (stackTrace != null) debugPrint(stackTrace.toString());
  }

  /// Release-visible diagnostic line: the exact behaviour of the bare
  /// `debugPrint` calls this replaces. Callers must only pass content
  /// that is safe to print in release (see the file doc comment).
  static void report(String message, {String? tag}) {
    debugPrint(_format('REPORT', tag, message, null, null));
  }

  static String _format(
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
