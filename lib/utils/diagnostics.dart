// Release-safe diagnostics for exceptions that are deliberately swallowed.
//
// Before this helper, ~28 `catch` blocks only called `debugPrint(...)`,
// which prints nothing useful in release builds: a swallowed failure left
// no trace at all. [logIgnored] keeps the same "do not crash, do not
// bother the user" behaviour but also records a bounded, in-memory trail
// that Settings / bug reports can dump.
//
// Privacy: only the tag, the exception TYPE and a timestamp are kept —
// never the message, URL or stack arguments, because exception text from
// the network layer can contain query strings, cookies or book links.
import 'dart:collection';

import 'package:flutter/foundation.dart';

class Diagnostics {
  Diagnostics._();

  /// Upper bound on retained entries (oldest are dropped first).
  static const int maxEntries = 200;

  static final Queue<String> _entries = Queue<String>();

  /// Records one swallowed failure.
  static void record(String tag, Object error) {
    final line =
        '${DateTime.now().toIso8601String()} [$tag] ${error.runtimeType}';
    _entries.addLast(line);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    if (kDebugMode) debugPrint(line);
  }

  /// Snapshot, oldest first.
  static List<String> snapshot() => List<String>.unmodifiable(_entries);

  /// All entries as one text blob (for "copy diagnostics").
  static String dump() => _entries.join('\n');

  @visibleForTesting
  static void clear() => _entries.clear();
}

/// Shorthand used by `catch` blocks that intentionally swallow [error].
void logIgnored(String tag, Object error) => Diagnostics.record(tag, error);
