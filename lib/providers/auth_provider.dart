import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import '../services/auth_storage.dart';
import '../services/challenge_html_cache.dart';
import '../services/hive_service.dart';
import 'books_provider.dart';
import 'domain_provider.dart';
import 'zlibrary_provider.dart';

class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;

  /// True when auth init couldn't reach the current line (cf_blocked / network error).
  /// User is treated as logged in via cached credentials, but UI should suggest switching.
  final bool lineUnavailable;

  AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.lineUnavailable = false,
  });

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
    bool? lineUnavailable,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      lineUnavailable: lineUnavailable ?? this.lineUnavailable,
    );
  }
}

/// Auth state notifier
class AuthNotifier extends Notifier<AuthState> {
  late final ZLibraryApi _api;
  final AuthStorage _storage = AuthStorage();

  @override
  AuthState build() {
    _api = ref.read(zlibraryApiProvider);
    _init();
    return AuthState(isLoading: true);
  }

  Future<void> _init() async {
    // No `state = state.copyWith(isLoading: true)` here: build() already
    // returns AuthState(isLoading: true) as the initial state, and reading
    // state inside build() would throw (not yet initialized).
    try {
      final credentials = await _storage.getCredentials();
      final userId = credentials['userId'];
      final userKey = credentials['userKey'];

      if (userId == null || userKey == null) {
        state = AuthState();
        return;
      }

      // Build a fallback User from cached fields so we can stay logged in
      // even when the current line is unreachable.
      User cachedUser() => User(
        id: userId,
        email: credentials['email'] ?? '',
        name: credentials['name'] ?? 'User',
        remixUserkey: userKey,
      );

      // A custom (non built-in) line persisted from a previous run must
      // never receive the stored session automatically at boot.
      final savedDomain =
          (HiveService.settingsBox.get('domain') as String?) ?? defaultDomain;
      if (!DomainNotifier.isBuiltInDomain(savedDomain)) {
        state = AuthState(user: cachedUser(), lineUnavailable: true);
        return;
      }

      try {
        // Use loginWithToken — it sets remix_userid/remix_userkey cookies on
        // Dio and hits /eapi/user/profile directly, so it works even on a
        // fresh boot when the api's internal _loggedIn flag is still false.
        final response = await _api.loginWithToken(userId, userKey);

        if (response.success && response.data != null) {
          state = AuthState(user: response.data);
        } else if (response.error == 'cf_blocked' ||
            _isTransientError(response.error)) {
          // Line is unreachable — keep credentials, suggest switching.
          state = AuthState(user: cachedUser(), lineUnavailable: true);
        } else {
          // Real auth failure (e.g. invalid token) — drop creds.
          await _storage.clearCredentials();
          state = AuthState();
        }
      } catch (e) {
        // Network exception — assume line issue, keep using cached creds.
        state = AuthState(user: cachedUser(), lineUnavailable: true);
      }
    } catch (e) {
      state = AuthState(error: e.toString());
    }
  }

  /// Heuristic: treat connection/timeout errors as transient line problems,
  /// not auth failures. We don't want to wipe credentials over a network blip.
  bool _isTransientError(String? error) {
    if (error == null) return false;
    final e = error.toLowerCase();
    return e.contains('line_error') ||
        e.contains('timeout') ||
        e.contains('socket') ||
        e.contains('connection') ||
        e.contains('network') ||
        e.contains('handshake') ||
        e.contains('unreachable') ||
        e.contains('failed host lookup') ||
        e.contains('request failed');
  }

  Future<bool> login(String email, String password) async {
    ChallengeHtmlCache.clear();
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _api.login(email, password);

      if (response.success && response.data != null) {
        final user = response.data!;

        await _storage.saveCredentials(
          userId: user.id,
          userKey: user.remixUserkey,
          email: user.email,
          name: user.name,
        );

        state = AuthState(user: user);
        return true;
      } else {
        state = AuthState(error: response.error ?? 'Login failed');
        return false;
      }
    } catch (e) {
      state = AuthState(error: e.toString());
      return false;
    }
  }

  Future<bool> loginWithToken(String userId, String userKey) async {
    ChallengeHtmlCache.clear();
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _api.loginWithToken(userId, userKey);

      if (response.success && response.data != null) {
        state = AuthState(user: response.data);
        return true;
      } else {
        state = AuthState(error: response.error ?? 'Token login failed');
        return false;
      }
    } catch (e) {
      state = AuthState(error: e.toString());
      return false;
    }
  }

  Future<void> logout() async {
    ChallengeHtmlCache.clear();
    await _storage.clearCredentials();
    // Session cookies installed for the online reader live in the WebView
    // cookie store; clear them too so logout really logs out everywhere.
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (error) {
      debugPrint('[auth_provider] ignored ${error.runtimeType}');
      // WebView never initialized — nothing to clear.
    }
    try {
      await WebStorageManager.instance().deleteAllData();
    } catch (error) { debugPrint('[auth_provider] ignored ${error.runtimeType}'); }
    try {
      await InAppWebViewController.clearAllCache();
    } catch (error) { debugPrint('[auth_provider] ignored ${error.runtimeType}'); }
    state = AuthState();
    // Same account-scoped caches as an account switch: a later login
    // as a different account must not see the old account's data.
    ref.invalidate(bookDetailsProvider);
    ref.invalidate(recommendedBooksProvider);
    ref.invalidate(mostPopularBooksProvider);
    ref.invalidate(recentBooksProvider);
    ref.invalidate(downloadedBooksProvider);
    ref.invalidate(savedBooksProvider);
  }

  /// Mark the current line unavailable without sending any credentials:
  /// used after switching to a custom domain, where the stored session
  /// must not be auto-sent until the user explicitly logs in again.
  void flagLineUnavailable() {
    state = state.copyWith(lineUnavailable: true);
  }

  Future<void> refreshProfile() async {
    if (!state.isAuthenticated) return;

    try {
      final response = await _api.getProfile();
      if (response.success && response.data != null) {
        state = AuthState(user: response.data);
      }
    } catch (e) {
      // Keep existing state on error
    }
  }

  /// Re-verify the current line/credentials. Used after the user switches
  /// network line to refresh the lineUnavailable flag and pick up real profile.
  Future<void> reverify() async {
    final credentials = await _storage.getCredentials();
    final userId = credentials['userId'];
    final userKey = credentials['userKey'];
    if (userId == null || userKey == null) return;

    try {
      final response = await _api.loginWithToken(userId, userKey);
      if (response.success && response.data != null) {
        state = AuthState(user: response.data);
      } else if (response.error == 'cf_blocked' ||
          _isTransientError(response.error)) {
        // Still unreachable — keep current user but mark line unavailable.
        state = state.copyWith(lineUnavailable: true);
      }
      // Other errors: leave existing state alone; user can logout manually.
    } catch (error) {
      debugPrint('[auth_provider] ignored ${error.runtimeType}');
      state = state.copyWith(lineUnavailable: true);
    }
  }

  Future<List<Map<dynamic, dynamic>>> getSavedAccounts() async {
    return await _storage.getStoredAccounts();
  }

  Future<bool> switchAccount(Map<String, dynamic> account) async {
    final userId = account['userId']?.toString();
    final userKey = account['userKey']?.toString();
    final email = account['email']?.toString();

    if (userId != null && userKey != null) {
      final success = await loginWithToken(userId, userKey);
      if (success) {
        await _storage.saveCredentials(
          userId: userId,
          userKey: userKey,
          email: state.user?.email ?? email,
          name: state.user?.name ?? account['name']?.toString(),
        );
        // Bust caches for anything that depends on the account, like
        // the line change does (see domain_provider): otherwise the
        // library keeps showing the previous account's books until a
        // manual refresh.
        ref.invalidate(bookDetailsProvider);
        ref.invalidate(recommendedBooksProvider);
        ref.invalidate(mostPopularBooksProvider);
        ref.invalidate(recentBooksProvider);
        ref.invalidate(downloadedBooksProvider);
        ref.invalidate(savedBooksProvider);
      }
      return success;
    }
    // No session keys and no stored password (passwords are never persisted):
    // this account cannot be switched to without logging in again.
    return false;
  }

  Future<void> removeAccount(String userId) async {
    await _storage.removeAccount(userId);
  }
}

/// Auth state provider
final authProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
