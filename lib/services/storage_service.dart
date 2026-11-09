import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      debugPrint('[storage] cannot resolve account id');
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
      debugPrint('[storage] ignoring corrupt favorites entry');
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
      debugPrint('[storage] favorites migration failed');
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

  // ===== Download History Methods =====
  
  /// Add book to download history
  /// Stores: {bookId: {title, author, filePath, cover, extension, downloadTime}}
  Future<void> addToDownloadHistory(
    String bookId, 
    String title, 
    String? author, 
    String filePath, 
    {String? cover, String? extension}
  ) async {
    final historyJson = HiveService.settingsBox.get(_keyDownloadHistory, defaultValue: '{}') as String;
    final history = Map<String, dynamic>.from(jsonDecode(historyJson));
    
    history[bookId] = {
      'title': title,
      'author': author,
      'filePath': filePath,
      'cover': cover,
      'extension': extension,
      'downloadTime': DateTime.now().toIso8601String(),
    };
    
    await HiveService.settingsBox.put(_keyDownloadHistory, jsonEncode(history));
  }

  /// Get all download history
  Future<Map<String, dynamic>> getDownloadHistory() async {
    final historyJson = HiveService.settingsBox.get(_keyDownloadHistory, defaultValue: '{}') as String;
    return Map<String, dynamic>.from(jsonDecode(historyJson));
  }

  /// Check if book was previously downloaded
  Future<bool> isBookDownloaded(String bookId) async {
    final history = await getDownloadHistory();
    return history.containsKey(bookId);
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
    final historyJson = HiveService.settingsBox.get(_keyDownloadHistory, defaultValue: '{}') as String;
    final history = Map<String, dynamic>.from(jsonDecode(historyJson));
    
    history.remove(bookId);
    
    await HiveService.settingsBox.put(_keyDownloadHistory, jsonEncode(history));
  }
}
