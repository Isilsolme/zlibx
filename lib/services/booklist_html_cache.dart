import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
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

  static Box get _box {
    final box = HiveService.booklistHtmlBox;
    _sweepTokenHtmlOnce(box);
    return box;
  }

  /// One-time purge of pre-existing cached HTML that still carries the
  /// signed-in user's `user_token` JWT. Older app versions stored the
  /// raw detail HTML verbatim; [store] now strips the token, so any
  /// entry that still has one predates the strip and is dropped once
  /// (the box is a rebuildable cache — it refills from the network).
  /// Runs at most once per process; entries without a token are
  /// untouched, and the 7-day TTL / 50-entry cap are unchanged.
  static bool _tokenSweepDone = false;

  static void _sweepTokenHtmlOnce(Box box) {
    if (_tokenSweepDone) return;
    _tokenSweepDone = true;
    for (final value in box.values) {
      if (value is Map &&
          value['html'] is String &&
          (value['html'] as String).contains('user_token=')) {
        unawaited(box.clear());
        return;
      }
    }
  }

  @visibleForTesting
  static void debugResetTokenSweep() {
    _tokenSweepDone = false;
  }

  /// Removes session credentials from cached HTML before it is
  /// persisted. The detail page carries the signed-in user's
  /// `user_token` JWT as a card attribute; the parser deliberately
  /// never reads it, and it must never reach Hive either.
  static String _stripSensitive(String html) {
    var clean = html.replaceAll(
      RegExp(r'''\suser_token="[^"]*"'''),
      '',
    );
    clean = clean.replaceAll(
      RegExp(r"""\suser_token='[^']*'"""),
      '',
    );
    return clean;
  }

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
    // Hive writes to memory synchronously, so the entry is visible to
    // readers (and to the eviction below) immediately; the returned
    // Future only covers the disk flush, which is intentionally
    // fire-and-forget.
    unawaited(box.put(key, value));
    _evictOldest(box);
  }

  static void store(String url, String html, {String? accountId}) {
    if (url.isEmpty || html.isEmpty) return;
    _put(_key(url, accountId), {
      'at': DateTime.now().millisecondsSinceEpoch,
      'html': _stripSensitive(html),
    });
  }

  /// Drops every cached entry for one booklist: the raw detail HTML
  /// plus all of its parsed JSON pages (page 1, 2, ...). Use after a
  /// write (add/remove a book, delete the list) so a later open
  /// re-fetches instead of painting stale rows.
  static void invalidateBooklist(String url, {String? accountId}) {
    if (url.isEmpty) return;
    final box = _box;
    box.delete(_key(url, accountId));
    invalidateBooklistPages(url, accountId: accountId);
  }

  /// Drops the parsed JSON pages (`#json-page=N`) of one booklist,
  /// leaving the raw HTML entry alone.
  static void invalidateBooklistPages(String url, {String? accountId}) {
    if (url.isEmpty) return;
    final box = _box;
    final prefix = '$url#json-page=';
    final suffix = accountId == null ? null : '#account=$accountId';
    final keys = box.keys.whereType<String>().where((key) {
      if (!key.startsWith(prefix)) return false;
      if (suffix == null) return !key.contains('#account=');
      return key.endsWith(suffix);
    }).toList();
    for (final key in keys) {
      box.delete(key);
    }
  }

  /// Deletes every entry older than [ttl] (and every entry with no
  /// usable timestamp). Expired entries otherwise linger until the
  /// 50-entry cap evicts them.
  static void pruneExpired() {
    final box = _box;
    final now = DateTime.now().millisecondsSinceEpoch;
    final keys = box.keys.where((key) {
      final raw = box.get(key);
      if (raw is! Map) return true;
      final at = raw['at'];
      if (at is! int) return true;
      return now - at > ttl.inMilliseconds;
    }).toList();
    for (final key in keys) {
      box.delete(key);
    }
  }

  /// The cached HTML for [url], or null when never cached or stale
  /// (older than [ttl]). A stored challenge page is returned as-is —
  /// callers reject it with the solver's challenge check, the same
  /// way they treat the in-memory cache. Expired or corrupt entries
  /// are deleted on read instead of lingering until eviction.
  static String? get(String url, {String? accountId}) {
    if (url.isEmpty) return null;
    final box = _box;
    final key = _key(url, accountId);
    final raw = box.get(key);
    if (raw is! Map) {
      if (raw != null) box.delete(key);
      return null;
    }
    final at = raw['at'];
    final html = raw['html'];
    if (at is! int || html is! String) {
      box.delete(key);
      return null;
    }
    if (DateTime.now().millisecondsSinceEpoch - at > ttl.inMilliseconds) {
      box.delete(key);
      return null;
    }
    return html;
  }

  static bool has(String url, {String? accountId}) =>
      get(url, accountId: accountId) != null;

  /// Books of one detail page (page 1 is HTML; page 2+ is JSON), or null
  /// when never cached, stale, or corrupt. The key is the detail URL + page,
  /// with the same account partition as [store]. Stale or corrupt
  /// entries are deleted on read instead of lingering until eviction.
  static List<Book>? getBooksPage(
    String url,
    int page, {
    String? accountId,
  }) {
    if (url.isEmpty) return null;
    final box = _box;
    final key = _key('$url#json-page=$page', accountId);
    final raw = box.get(key);
    if (raw is! Map) {
      if (raw != null) box.delete(key);
      return null;
    }
    final at = raw['at'];
    final books = raw['books'];
    if (at is! int || books is! List) {
      box.delete(key);
      return null;
    }
    if (DateTime.now().millisecondsSinceEpoch - at > ttl.inMilliseconds) {
      box.delete(key);
      return null;
    }
    try {
      return books
          .whereType<Map>()
          .map((item) => Book.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (error) {
      debugPrint('[booklist_html_cache] ignored ${error.runtimeType}');
      box.delete(key);
      return null;
    }
  }

  static void storeBooksPage(
    String url,
    int page,
    List<Book> books, {
    String? accountId,
  }) {
    if (url.isEmpty) return;
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
