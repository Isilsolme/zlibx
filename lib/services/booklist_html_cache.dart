import 'package:hive_flutter/hive_flutter.dart';

import 'hive_service.dart';

/// Persistent (Hive) cache for booklist HTML pages, keyed by the
/// page's full URL — the same key convention as the in-memory
/// ChallengeHtmlCache (10-minute TTL, dies on restart).
///
/// Screens paint the last-known page from here instantly, then refresh
/// in the background (stale-while-revalidate); a failed refresh keeps
/// the cached data on screen. Raw HTML is cached, not parsed models,
/// so the existing parsers stay the single source of truth — a cached
/// page is re-parsed on every read, exactly like a fresh load.
class BooklistHtmlCache {
  BooklistHtmlCache._();

  /// Hive box name, shared with [HiveService].
  static const String boxName = HiveService.booklistHtmlBoxName;

  /// Entries older than this read as absent (cold load, as today).
  /// Booklists change slowly; a week bounds staleness while the
  /// background refresh keeps fresh opens up to date.
  static const Duration ttl = Duration(days: 7);

  /// Upper bound on stored pages (each page is tens to low hundreds
  /// of kilobytes); the oldest entries are evicted on store.
  static const int maxEntries = 50;

  static Box get _box => HiveService.booklistHtmlBox;

  static void store(String url, String html) {
    if (url.isEmpty || html.isEmpty) return;
    final box = _box;
    box.put(url, {
      'at': DateTime.now().millisecondsSinceEpoch,
      'html': html,
    });
    _evictOldest(box);
  }

  /// The cached HTML for [url], or null when never cached or stale
  /// (older than [ttl]). A stored challenge page is returned as-is —
  /// callers reject it with the solver's challenge check, the same
  /// way they treat the in-memory cache.
  static String? get(String url) {
    if (url.isEmpty) return null;
    final raw = _box.get(url);
    if (raw is! Map) return null;
    final at = raw['at'];
    final html = raw['html'];
    if (at is! int || html is! String) return null;
    if (DateTime.now().millisecondsSinceEpoch - at > ttl.inMilliseconds) {
      return null;
    }
    return html;
  }

  static bool has(String url) => get(url) != null;

  static void clear() => _box.clear();

  static void _evictOldest(Box box) {
    if (box.length <= maxEntries) return;
    // Entries carry their own timestamp; drop the oldest until the
    // cap holds. A corrupt entry (no usable timestamp) counts as
    // oldest so it is evicted first.
    final atByKey = <Object?, int>{};
    for (final key in box.keys) {
      final raw = box.get(key);
      var at = 0;
      if (raw is Map && raw['at'] is int) at = raw['at'] as int;
      atByKey[key] = at;
    }
    final keys = atByKey.keys.toList()
      ..sort((a, b) => atByKey[a]!.compareTo(atByKey[b]!));
    for (var i = 0; i < keys.length - maxEntries; i++) {
      box.delete(keys[i]);
    }
  }
}
