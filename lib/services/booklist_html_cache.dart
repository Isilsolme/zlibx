import 'package:hive_flutter/hive_flutter.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

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
///
/// Account-scoped pages (the own-lists page and booklist detail
/// pages) are additionally partitioned by the signed-in account:
/// the same URL serves another account's lists after a switch, so
/// those entries carry an `#account=<id>` suffix on the key. Public
/// pages (discover, profile — the profile URL already carries the
/// viewed user's id + hash) use the plain URL.
///
/// The detail JSON pages (page 2+, `get-books`) are cached here too,
/// as parsed books via `Book.toJson` / `Book.fromJson` — the plugin
/// does not expose the raw JSON body to the app layer, so this is
/// the one place where parsed-model serialization is used. JSON
/// entries share the box-wide TTL and entry cap with the HTML pages.
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

  /// Whether a booklist page URL is account-scoped: the own-lists
  /// page (`/booklists/my`) and booklist detail pages
  /// (`/booklist/{id}/...`). Discover (`/booklists`) and profile
  /// pages (`/profile/{id}/{hash}`) are not.
  static bool isPrivateUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    return path == '/booklists/my' || path.startsWith('/booklist/');
  }

  /// Key for one entry: the plain URL for public pages, the URL with
  /// an `#account=<id>` suffix for account-scoped pages. Callers
  /// pass the signed-in user id (or `'signed-out'`) for private
  /// pages and leave [accountId] null for public ones.
  static String _key(String url, String? accountId) =>
      accountId == null ? url : '$url#account=$accountId';

  static void _put(Object key, Map<String, Object> value) {
    final box = _box;
    box.put(key, value);
    _evictOldest(box);
  }

  static void store(String url, String html, {String? accountId}) {
    if (url.isEmpty || html.isEmpty) return;
    _put(_key(url, accountId), {
      'at': DateTime.now().millisecondsSinceEpoch,
      'html': html,
    });
  }

  /// The cached HTML for [url], or null when never cached or stale
  /// (older than [ttl]). A stored challenge page is returned as-is —
  /// callers reject it with the solver's challenge check, the same
  /// way they treat the in-memory cache.
  static String? get(String url, {String? accountId}) {
    if (url.isEmpty) return null;
    final raw = _box.get(_key(url, accountId));
    if (raw is! Map) return null;
    final at = raw['at'];
    final html = raw['html'];
    if (at is! int || html is! String) return null;
    if (DateTime.now().millisecondsSinceEpoch - at > ttl.inMilliseconds) {
      return null;
    }
    return html;
  }

  static bool has(String url, {String? accountId}) =>
      get(url, accountId: accountId) != null;

  /// Books of one detail JSON page (page 2+), or null when never
  /// cached, stale, or corrupt. The key is the detail URL + page,
  /// with the same account partition as [store].
  static List<Book>? getBooksPage(
    String url,
    int page, {
    String? accountId,
  }) {
    if (url.isEmpty) return null;
    final raw = _box.get(_key('$url#json-page=$page', accountId));
    if (raw is! Map) return null;
    final at = raw['at'];
    final books = raw['books'];
    if (at is! int || books is! List) return null;
    if (DateTime.now().millisecondsSinceEpoch - at > ttl.inMilliseconds) {
      return null;
    }
    try {
      return books
          .whereType<Map>()
          .map((item) => Book.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static void storeBooksPage(
    String url,
    int page,
    List<Book> books, {
    String? accountId,
  }) {
    if (url.isEmpty || books.isEmpty) return;
    _put(_key('$url#json-page=$page', accountId), {
      'at': DateTime.now().millisecondsSinceEpoch,
      'books': books.map((book) => book.toJson()).toList(),
    });
  }

  static Future<void> clear() => _box.clear();

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
