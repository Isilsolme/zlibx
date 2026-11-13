import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/app_log.dart';
import 'auth_storage.dart';
import 'hive_service.dart';

/// Riverpod provider for StorageService (singleton)
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

class StorageService {
  /// Legacy shared favorites key: every account read and wrote the
  /// same list. Kept only so the one-time migration can find it — no
  /// favorites read/write uses it anymore (see [favoritesKeyFor]).
  static const String _keyFavorites = 'favorite_books';
  // _keyDownloads was removed with the dead saveDownloadedBook() method:
  // it stored `bookInfo.toString()` (a Dart debug string, not JSON, not
  // parseable) and had no callers — download history lives in
  // _keyDownloadHistory below.
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyDownloadPath = 'download_path';
  static const String _keyDownloadHistory = 'download_history';

  /// Per-account favorites key: `favorite_books_<accountId>`.
  /// The account id is the Z-Library user id (a String — see User.id),
  /// the same value stored as the `remix_userid` credential, so the
  /// key follows the signed-in account and never a display name or
  /// email. Each account reads and writes only its own key, which is
  /// what keeps the local hearts in sync with the account-scoped
  /// server list after a switch.
  static String favoritesKeyFor(String accountId) =>
      '${_keyFavorites}_$accountId';

  /// The signed-in account's id, or null when signed out or when the
  /// stored credentials cannot be read (secure storage unavailable).
  /// A null here means "no account to scope to": reads see nothing and
  /// writes refuse, rather than touching the shared legacy key.
  Future<String?> _currentAccountId() async {
    try {
      final userId = (await AuthStorage().getCredentials())['userId'];
      return (userId == null || userId.isEmpty) ? null : userId;
    } catch (error) {
      AppLog.report('[storage] cannot resolve account id', tag: 'storage_service');
      return null;
    }
  }

  /// Read one favorites list from Hive, tolerating a corrupt entry
  /// (wrong type, non-string ids) as empty instead of crashing the
  /// caller. A corrupt legacy entry must not block the migration.
  List<String> _readFavoritesForKey(String key) {
    final data = HiveService.settingsBox.get(key);
    if (data is! List) return [];
    try {
      return List<String>.from(data);
    } catch (error) {
      AppLog.report('[storage] ignoring corrupt favorites entry', tag: 'storage_service');
      return [];
    }
  }

  /// One-time migration of the legacy shared favorites list to the
  /// account signed in right now. Runs lazily at the start of every
  /// favorites operation (and once eagerly at startup from main):
  /// - No signed-in account: does nothing and leaves the legacy key
  ///   in place, so a later login can still migrate it. Nothing is
  ///   ever migrated to an empty account id.
  /// - Legacy key absent or empty: nothing to do.
  /// - Target key already has favorites: merged (target order first,
  ///   then legacy ids not already present) — the old list never
  ///   overwrites the account's own list.
  /// - Afterwards the legacy key is deleted: that deletion is what
  ///   makes the migration run exactly once. A second call finds no
  ///   legacy key and returns immediately.
  /// Never throws: a storage failure leaves the legacy key untouched
  /// so the next call retries instead of losing data.
  Future<void> migrateLegacyFavorites() async {
    final accountId = await _currentAccountId();
    if (accountId == null) return;
    await migrateLegacyFavoritesFor(accountId);
  }

  /// Same migration for an explicit account id. Public (instead of
  /// private) so tests can drive it without a signed-in account.
  Future<void> migrateLegacyFavoritesFor(String accountId) async {
    if (accountId.isEmpty) return;
    try {
      final box = HiveService.settingsBox;
      if (!box.containsKey(_keyFavorites)) return;
      final legacy = _readFavoritesForKey(_keyFavorites);
      if (legacy.isNotEmpty) {
        final targetKey = favoritesKeyFor(accountId);
        final merged = _readFavoritesForKey(targetKey);
        for (final id in legacy) {
          if (!merged.contains(id)) merged.add(id);
        }
        await box.put(targetKey, merged);
      }
      await box.delete(_keyFavorites);
    } catch (error) {
      AppLog.report('[storage] favorites migration failed', tag: 'storage_service');
    }
  }

  /// Save favorite book IDs for the signed-in account. Throws
  /// [StateError] when signed out: there is no account key to write
  /// to, and silently dropping the write would lose the favorite.
  Future<void> saveFavorites(List<String> bookIds) async {
    final accountId = await _currentAccountId();
    if (accountId == null) {
      throw StateError('cannot save favorites: no signed-in account');
    }
    await migrateLegacyFavoritesFor(accountId);
    await HiveService.settingsBox.put(
      favoritesKeyFor(accountId),
      bookIds,
    );
  }

  /// Get favorite book IDs for the signed-in account ([] when signed
  /// out — a signed-out user has no account list to show).
  Future<List<String>> getFavorites() async {
    final accountId = await _currentAccountId();
    if (accountId == null) return [];
    await migrateLegacyFavoritesFor(accountId);
    return _readFavoritesForKey(favoritesKeyFor(accountId));
  }

  /// Synchronous read of one account's favorites, for callers that
  /// already know the account id. Prefer [getFavorites].
  List<String> getFavoritesSyncForAccount(String accountId) =>
      _readFavoritesForKey(favoritesKeyFor(accountId));

  /// Add a book to the signed-in account's favorites. Throws
  /// [StateError] when signed out (see [saveFavorites]).
  Future<void> addFavorite(String bookId) async {
    final accountId = await _currentAccountId();
    if (accountId == null) {
      throw StateError('cannot add favorite: no signed-in account');
    }
    await migrateLegacyFavoritesFor(accountId);
    final key = favoritesKeyFor(accountId);
    final favorites = _readFavoritesForKey(key);
    if (!favorites.contains(bookId)) {
      favorites.add(bookId);
      await HiveService.settingsBox.put(key, favorites);
    }
  }

  /// Remove a book from the signed-in account's favorites. Throws
  /// [StateError] when signed out (see [saveFavorites]).
  Future<void> removeFavorite(String bookId) async {
    final accountId = await _currentAccountId();
    if (accountId == null) {
      throw StateError('cannot remove favorite: no signed-in account');
    }
    await migrateLegacyFavoritesFor(accountId);
    final key = favoritesKeyFor(accountId);
    final favorites = _readFavoritesForKey(key);
    favorites.remove(bookId);
    await HiveService.settingsBox.put(key, favorites);
  }

  /// Check whether a book is in the signed-in account's favorites
  /// (false when signed out).
  Future<bool> isFavorite(String bookId) async {
    final accountId = await _currentAccountId();
    if (accountId == null) return false;
    await migrateLegacyFavoritesFor(accountId);
    final favorites = _readFavoritesForKey(favoritesKeyFor(accountId));
    return favorites.contains(bookId);
  }

  /// Get theme mode (0: system, 1: light, 2: dark)
  Future<int> getThemeMode() async {
    return HiveService.settingsBox.get(_keyThemeMode, defaultValue: 0) as int;
  }

  /// Set theme mode
  Future<void> setThemeMode(int mode) async {
    await HiveService.settingsBox.put(_keyThemeMode, mode);
  }

  /// Get download path
  Future<String?> getDownloadPath() async {
    return HiveService.settingsBox.get(_keyDownloadPath) as String?;
  }

  /// Set download path
  Future<void> setDownloadPath(String path) async {
    await HiveService.settingsBox.put(_keyDownloadPath, path);
  }

  // ===== Serialized whole-blob JSON writes =====
  //
  // The download history is one JSON blob in the settings box. A Hive
  // `put` is async, so two concurrent read-modify-write calls for the
  // same key would both read the same stale blob — the second write then
  // silently drops the first one's entry. Chaining each write onto the
  // previous write for the same key makes the read-modify-write atomic
  // per key: a chained write only reads after the previous write's `put`
  // completed. Pure reads are NOT serialized (they may see a slightly
  // stale snapshot — acceptable for a cache). The map is static on
  // purpose: the Hive box is global and StorageService is constructed
  // directly outside the Riverpod singleton, so an instance field would
  // not serialize writes across instances.
  static final Map<String, Future<void>> _writeChains = {};

  /// Run [work] after the previous write for [key] finished, and return
  /// [work]'s own future to the caller. The stored chain future never
  /// completes with an error — a failed write is swallowed in the chain —
  /// so one failure does not block later writers for the same key; the
  /// caller still sees its own result/error through the returned future.
  static Future<T> _runSerialized<T>(String key, Future<T> Function() work) {
    final previous = _writeChains[key];
    final run = (previous ?? Future<void>.value()).then((_) => work());
    _writeChains[key] = run.then<void>((_) {}).catchError((_, __) {});
    return run;
  }

  // ===== Download History Methods =====

  /// Read the local download-history blob, tolerating a corrupt entry
  /// instead of crashing the caller. Returns {} when the key is absent
  /// (the defaultValue '{}' below), when the stored value is not a
  /// String, when it is not valid JSON, or when the top-level value is
  /// not a Map. A corrupt value is moved to an isolation backup key (see
  /// [_quarantineDownloadHistory]). Entries whose value is not a Map are
  /// dropped, so a malformed entry cannot break a later field read.
  Future<Map<String, dynamic>> _readDownloadHistorySafely() async {
    final raw = HiveService.settingsBox.get(
      _keyDownloadHistory,
      defaultValue: '{}',
    );
    if (raw is! String) {
      await _quarantineDownloadHistory(raw);
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await _quarantineDownloadHistory(raw);
        return {};
      }
      final history = <String, dynamic>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map) {
          history['${entry.key}'] = Map<String, dynamic>.from(
            entry.value as Map,
          );
        }
      }
      return history;
    } catch (_) {
      await _quarantineDownloadHistory(raw);
      return {};
    }
  }

  /// Move a corrupt download-history value to an isolation backup key and
  /// log the corruption (without the raw value) so the bad entry is
  /// preserved for inspection instead of being overwritten. Best-effort:
  /// a failed backup must not break the read that found the corruption.
  Future<void> _quarantineDownloadHistory(Object? raw) async {
    AppLog.report(
      '[storage] ignoring corrupt download history entry',
      tag: 'storage_service',
    );
    try {
      await HiveService.settingsBox.put(
        '${_keyDownloadHistory}_corrupt',
        raw,
      );
    } catch (_) {
      // Best-effort backup; the read already returns {}.
    }
  }

  /// Add book to download history
  /// Stores: {bookId: {title, author, filePath, cover, extension, downloadTime}}
  Future<void> addToDownloadHistory(
    String bookId,
    String title,
    String? author,
    String filePath, {
    String? cover,
    String? extension,
  }) async {
    await _runSerialized(_keyDownloadHistory, () async {
      final history = await _readDownloadHistorySafely();

      history[bookId] = {
        'title': title,
        'author': author,
        'filePath': filePath,
        'cover': cover,
        'extension': extension,
        'downloadTime': DateTime.now().toIso8601String(),
      };

      await HiveService.settingsBox.put(
        _keyDownloadHistory,
        jsonEncode(history),
      );
    });
  }

  /// Get all download history
  Future<Map<String, dynamic>> getDownloadHistory() async {
    return _readDownloadHistorySafely();
  }

  /// Get downloaded file path for a book
  Future<String?> getDownloadedFilePath(String bookId) async {
    final history = await getDownloadHistory();
    if (history.containsKey(bookId)) {
      return history[bookId]['filePath'] as String?;
    }
    return null;
  }

  /// Remove book from download history
  Future<void> removeFromDownloadHistory(String bookId) async {
    await _runSerialized(_keyDownloadHistory, () async {
      final history = await _readDownloadHistorySafely();

      history.remove(bookId);

      await HiveService.settingsBox.put(
        _keyDownloadHistory,
        jsonEncode(history),
      );
    });
  }
}
